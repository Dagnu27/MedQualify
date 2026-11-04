import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import express from 'express';
import bcrypt from 'bcryptjs';
import PDFDocument from 'pdfkit';
import ExcelJS from 'exceljs';
import {
  BorderStyle,
  Document,
  HeadingLevel,
  Packer,
  Paragraph,
  ShadingType,
  Table,
  TableCell,
  TableRow,
  TextRun,
  WidthType,
} from 'docx';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..', '..');
const checklistTemplates = JSON.parse(fs.readFileSync(path.join(__dirname, 'checklistData.json'), 'utf8'));
const port = Number(process.env.PORT || 3001);
const databasePath = path.resolve(process.env.DATABASE_PATH || path.join(__dirname, 'data', 'careaudit.sqlite'));
const sessionCookie = 'care_session';
const sessionMaxAge = 60 * 60 * 24 * 7;
const secureCookie = process.env.NODE_ENV === 'production' ? '; Secure' : '';
const defaultAdmin = { name: 'CareAudit Administrator', username: 'admin', password: '12345678' };

fs.mkdirSync(path.dirname(databasePath), { recursive: true });
const db = new DatabaseSync(databasePath);
db.exec('PRAGMA foreign_keys = ON');

function all(sql, ...params) {
  return db.prepare(sql).all(...params);
}

function one(sql, ...params) {
  return db.prepare(sql).get(...params);
}

function run(sql, ...params) {
  return db.prepare(sql).run(...params);
}

function id() {
  return crypto.randomUUID();
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function parsePayload(value) {
  if (Buffer.isBuffer(value)) value = value.toString('utf8');
  if (typeof value !== 'string') return value || {};
  try { return JSON.parse(value); } catch { return {}; }
}

function signatureImage(signature) {
  const match = typeof signature === 'string' && signature.match(/^data:image\/png;base64,([A-Za-z0-9+/]+={0,2})$/);
  if (!match || match[1].length > 700000) return null;
  const image = Buffer.from(match[1], 'base64');
  const pngHeader = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const isPng = image.length >= 45
    && image.subarray(0, pngHeader.length).equals(pngHeader)
    && image.readUInt32BE(8) === 13
    && image.toString('ascii', 12, 16) === 'IHDR'
    && image.readUInt32BE(16) > 0
    && image.readUInt32BE(16) <= 4096
    && image.readUInt32BE(20) > 0
    && image.readUInt32BE(20) <= 4096
    && image.readUInt32BE(image.length - 12) === 0
    && image.toString('ascii', image.length - 8, image.length - 4) === 'IEND';
  return isPng && image.toString('base64') === match[1] ? image : null;
}

function completeSigner(signer) {
  return typeof signer?.name === 'string'
    && signer.name.trim().length > 0
    && signer.name.trim().length <= 200
    && signatureImage(signer.signature) !== null;
}

function parseCookies(header = '') {
  return Object.fromEntries(header.split(';').map((part) => part.trim().split('=').map(decodeURIComponent)).filter(([key, value]) => key && value));
}

function setSessionCookie(response, token) {
  response.setHeader('Set-Cookie', `${sessionCookie}=${encodeURIComponent(token)}; Path=/; HttpOnly${secureCookie}; SameSite=Lax; Max-Age=${sessionMaxAge}`);
}

function clearSessionCookie(response) {
  response.setHeader('Set-Cookie', `${sessionCookie}=; Path=/; HttpOnly${secureCookie}; SameSite=Lax; Max-Age=0`);
}

function publicUser(row) {
  return { id: row.id, role: row.role, name: row.name, username: row.username, active: Boolean(row.active), createdAt: row.created_at };
}

function reportData(record, template) {
  const responses = record.responses || {};
  const scoreFor = (item) => {
    const status = responses[item.id]?.status;
    return status === 'met' || status === 'available' ? 1 : status === 'partial' ? 0.5 : 0;
  };
  const sectionScores = template.sections.map((section) => {
    const scored = section.items.filter((item) => item.scored !== false
      && (!item.optional || (responses[item.id]?.status && responses[item.id].status !== 'na')));
    const score = scored.length ? Math.round((scored.reduce((sum, item) => sum + scoreFor(item), 0) / scored.length) * 100) : 0;
    return { ...section, score, items: section.items.map((item) => ({ ...item, response: responses[item.id] || {} })) };
  });
  const allItems = sectionScores.flatMap((section) => section.items.map((item) => ({ ...item, sectionTitle: section.title })));
  const eligible = allItems.filter((item) => item.scored !== false
    && (!item.optional || (item.response.status && item.response.status !== 'na')));
  const gaps = allItems.filter((item) => item.response.status === 'unmet'
    || item.response.status === 'not-available'
    || (!item.optional && !item.response.status));
  const unanswered = allItems.filter((item) => !item.optional && !item.response.status);
  const score = eligible.length ? Math.round((eligible.reduce((sum, item) => sum + scoreFor(item), 0) / eligible.length) * 100) : 0;
  const labels = { met: 'Met', partial: 'Partially met', unmet: 'Unmet', available: 'Available', 'not-available': 'Not available', na: 'Not applicable' };
  return {
    sections: sectionScores,
    gaps,
    score,
    critical: gaps.filter((item) => item.severity === 'critical').length,
    major: gaps.filter((item) => item.severity === 'major').length,
    unanswered: unanswered.length,
    statusLabel: (status) => labels[status] || 'Not assessed',
  };
}

function validateCredentials({ name, username, password }, requireName = false) {
  if (requireName && (!name || !name.trim())) return 'Name is required.';
  if (!username || !/^[a-zA-Z0-9._-]{2,80}$/.test(username.trim())) return 'Username must be 2–80 letters, numbers, dots, underscores, or hyphens.';
  if (!password || password.length < 6 || password.length > 200) return 'Password must be between 6 and 200 characters.';
  return null;
}

async function ensureSchema() {
  db.exec(`CREATE TABLE IF NOT EXISTS careaudit_users (
    id TEXT NOT NULL PRIMARY KEY,
    role TEXT NOT NULL CHECK (role IN ('admin', 'inspector')),
    name TEXT NOT NULL,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
  );
  CREATE INDEX IF NOT EXISTS idx_careaudit_users_role ON careaudit_users(role);
  CREATE TABLE IF NOT EXISTS careaudit_sessions (
    token_hash TEXT NOT NULL PRIMARY KEY,
    user_id TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES careaudit_users(id) ON DELETE CASCADE
  );
  CREATE INDEX IF NOT EXISTS idx_careaudit_sessions_user ON careaudit_sessions(user_id);
  CREATE INDEX IF NOT EXISTS idx_careaudit_sessions_expiry ON careaudit_sessions(expires_at);
  CREATE TABLE IF NOT EXISTS careaudit_inspections (
    record_id TEXT NOT NULL PRIMARY KEY,
    inspector_id TEXT NOT NULL,
    facility_name TEXT NOT NULL,
    template_id TEXT NOT NULL,
    payload TEXT NOT NULL CHECK (json_valid(payload)),
    status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('draft', 'completed')),
    submitted_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (inspector_id) REFERENCES careaudit_users(id) ON DELETE CASCADE
  );
  CREATE INDEX IF NOT EXISTS idx_careaudit_inspections_inspector ON careaudit_inspections(inspector_id);
  CREATE INDEX IF NOT EXISTS idx_careaudit_inspections_submitted ON careaudit_inspections(submitted_at);`);
  const inspectionColumns = all('PRAGMA table_info(careaudit_inspections)');
  if (!inspectionColumns.some((column) => column.name === 'status')) {
    db.exec("ALTER TABLE careaudit_inspections ADD COLUMN status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('draft', 'completed'))");
  }
  const admins = all("SELECT id FROM careaudit_users WHERE role = 'admin' LIMIT 1");
  if (admins.length === 0) {
    run('INSERT INTO careaudit_users (id, role, name, username, password_hash) VALUES (?, \'admin\', ?, ?, ?)', id(), defaultAdmin.name, defaultAdmin.username, await bcrypt.hash(defaultAdmin.password, 12));
  }
}

async function authenticated(request, response, next) {
  try {
    const token = parseCookies(request.headers.cookie)[sessionCookie];
    if (!token) return response.status(401).json({ error: 'Not signed in.' });
    const user = one(`SELECT u.* FROM careaudit_sessions s JOIN careaudit_users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.expires_at > CURRENT_TIMESTAMP AND u.active = 1 LIMIT 1`, hashToken(token));
    if (!user) return response.status(401).json({ error: 'Session expired.' });
    request.user = user;
    return next();
  } catch (error) {
    return next(error);
  }
}

function adminOnly(request, response, next) {
  if (request.user?.role !== 'admin') return response.status(403).json({ error: 'Admin access required.' });
  return next();
}

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '2mb' }));

app.get('/api/health', async (_request, response) => {
  try {
    one('SELECT 1');
    response.json({ ok: true, service: 'careaudit', database: 'ready' });
  } catch {
    response.status(503).json({ ok: false, service: 'careaudit', database: 'unavailable' });
  }
});

app.get('/api/auth/status', async (_request, response, next) => {
  try {
    const row = one("SELECT COUNT(*) AS count FROM careaudit_users WHERE role = 'admin'");
    response.json({ hasAdmin: Number(row.count) > 0 });
  } catch (error) { next(error); }
});

app.get('/api/auth/me', authenticated, (request, response) => response.json({ user: publicUser(request.user) }));

app.post('/api/auth/login', async (request, response, next) => {
  try {
    const { role, username, password } = request.body || {};
    if (!['admin', 'inspector'].includes(role) || !username || !password) return response.status(400).json({ error: 'Role, username, and password are required.' });
    const user = one('SELECT * FROM careaudit_users WHERE username = ? AND role = ? LIMIT 1', username.trim().toLowerCase(), role);
    if (!user || !user.active || !(await bcrypt.compare(password, user.password_hash))) return response.status(401).json({ error: `${role === 'admin' ? 'Admin' : 'Inspector'} username or password is not correct.` });
    const token = crypto.randomBytes(32).toString('hex');
    run('DELETE FROM careaudit_sessions WHERE expires_at <= CURRENT_TIMESTAMP');
    run("INSERT INTO careaudit_sessions (token_hash, user_id, expires_at) VALUES (?, ?, datetime('now', '+7 days'))", hashToken(token), user.id);
    setSessionCookie(response, token);
    response.json({ user: publicUser(user) });
  } catch (error) { next(error); }
});

app.post('/api/auth/logout', async (request, response, next) => {
  try {
    const token = parseCookies(request.headers.cookie)[sessionCookie];
    if (token) run('DELETE FROM careaudit_sessions WHERE token_hash = ?', hashToken(token));
    clearSessionCookie(response);
    response.json({ ok: true });
  } catch (error) { next(error); }
});

app.get('/api/admin/overview', authenticated, adminOnly, async (request, response, next) => {
  try {
    const rows = all("SELECT id, name, username, active, created_at FROM careaudit_users WHERE role = 'inspector' ORDER BY created_at DESC");
    response.json({ admin: publicUser(request.user), inspectors: rows.map(publicUser) });
  } catch (error) { next(error); }
});

app.post('/api/admin/inspectors', authenticated, adminOnly, async (request, response, next) => {
  try {
    const { name, username, password } = request.body || {};
    const validation = validateCredentials({ name, username, password }, true);
    if (validation) return response.status(400).json({ error: validation });
    const normalized = username.trim().toLowerCase();
    const existing = one('SELECT id FROM careaudit_users WHERE username = ? LIMIT 1', normalized);
    if (existing) return response.status(409).json({ error: 'That username is already in use.' });
    const inspectorId = id();
    run('INSERT INTO careaudit_users (id, role, name, username, password_hash) VALUES (?, \'inspector\', ?, ?, ?)', inspectorId, name.trim(), normalized, await bcrypt.hash(password, 12));
    const created = one('SELECT id, role, name, username, active, created_at FROM careaudit_users WHERE id = ?', inspectorId);
    response.status(201).json({ inspector: publicUser(created) });
  } catch (error) { next(error); }
});

app.patch('/api/admin/inspectors/:id', authenticated, adminOnly, async (request, response, next) => {
  try {
    const active = Boolean(request.body?.active);
    const result = run("UPDATE careaudit_users SET active = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND role = 'inspector'", active ? 1 : 0, request.params.id);
    if (!result.changes) return response.status(404).json({ error: 'Inspector account not found.' });
    response.json({ ok: true });
  } catch (error) { next(error); }
});

app.post('/api/admin/inspectors/:id/reset-password', authenticated, adminOnly, async (request, response, next) => {
  try {
    const password = request.body?.password;
    if (!password || password.length < 6 || password.length > 200) return response.status(400).json({ error: 'Password must be between 6 and 200 characters.' });
    const result = run("UPDATE careaudit_users SET password_hash = ?, active = 1, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND role = 'inspector'", await bcrypt.hash(password, 12), request.params.id);
    if (!result.changes) return response.status(404).json({ error: 'Inspector account not found.' });
    response.json({ ok: true });
  } catch (error) { next(error); }
});

app.put('/api/admin/profile', authenticated, adminOnly, async (request, response, next) => {
  try {
    const { name, username, currentPassword, newPassword } = request.body || {};
    if (!name?.trim() || !username?.trim() || !currentPassword) return response.status(400).json({ error: 'Name, username, and current password are required.' });
    if (newPassword && (newPassword.length < 6 || newPassword.length > 200)) return response.status(400).json({ error: 'New password must be between 6 and 200 characters.' });
    if (!(await bcrypt.compare(currentPassword, request.user.password_hash))) return response.status(401).json({ error: 'The current admin password is not correct.' });
    const normalized = username.trim().toLowerCase();
    const existing = one('SELECT id FROM careaudit_users WHERE username = ? AND id <> ? LIMIT 1', normalized, request.user.id);
    if (existing) return response.status(409).json({ error: 'That username is already assigned to another account.' });
    const passwordHash = newPassword ? await bcrypt.hash(newPassword, 12) : request.user.password_hash;
    run('UPDATE careaudit_users SET name = ?, username = ?, password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?', name.trim(), normalized, passwordHash, request.user.id);
    const updated = one('SELECT id, role, name, username, active, created_at FROM careaudit_users WHERE id = ?', request.user.id);
    response.json({ admin: publicUser(updated) });
  } catch (error) { next(error); }
});

app.get('/api/inspections', authenticated, async (request, response, next) => {
  try {
    const rows = request.user.role === 'admin'
      ? all(`SELECT i.record_id, i.payload, i.status, i.submitted_at, u.name AS inspector_name
        FROM careaudit_inspections i
        JOIN careaudit_users u ON u.id = i.inspector_id
        WHERE i.status = 'completed'
        ORDER BY i.submitted_at DESC`)
      : all(`SELECT i.record_id, i.payload, i.status, i.submitted_at, i.updated_at, u.name AS inspector_name
        FROM careaudit_inspections i
        JOIN careaudit_users u ON u.id = i.inspector_id
        WHERE i.inspector_id = ?
        ORDER BY i.updated_at DESC`, request.user.id);
    const inspections = rows.map((row) => ({
      ...parsePayload(row.payload),
      id: row.record_id,
      status: row.status,
      submittedAt: row.submitted_at,
      inspectorName: row.inspector_name,
    }));
    response.json({ inspections });
  } catch (error) { next(error); }
});

app.put('/api/inspections/:id', authenticated, async (request, response, next) => {
  try {
    if (request.user.role !== 'inspector') return response.status(403).json({ error: 'Only inspectors can save inspections.' });
    const record = request.body?.record;
    if (!record?.id || record.id !== request.params.id || !record.templateId || !['draft', 'completed'].includes(record.status)) {
      return response.status(400).json({ error: 'A valid inspection record is required.' });
    }
    if (!checklistTemplates.some((template) => template.id === record.templateId)) {
      return response.status(400).json({ error: 'The selected checklist is not available.' });
    }
    if (record.status === 'completed') {
      if (!record.metadata?.facilityName?.trim()) return response.status(400).json({ error: 'A facility name is required to complete an inspection.' });
      const inspectors = record.signatures?.inspectors;
      if (!Array.isArray(inspectors) || !completeSigner(inspectors[0]) || !completeSigner(record.signatures?.pharmacist)) {
        return response.status(400).json({ error: 'One inspector name and drawn signature, plus the pharmacist name and drawn signature, are required.' });
      }
    }
    const existing = one('SELECT inspector_id FROM careaudit_inspections WHERE record_id = ? LIMIT 1', record.id);
    if (existing && existing.inspector_id !== request.user.id) return response.status(403).json({ error: 'This inspection belongs to another inspector.' });
    const facilityName = typeof record.metadata?.facilityName === 'string' ? record.metadata.facilityName.trim() : '';
    const payload = JSON.stringify(record);
    run(`INSERT INTO careaudit_inspections (record_id, inspector_id, facility_name, template_id, payload, status)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(record_id) DO UPDATE SET
        payload = excluded.payload,
        facility_name = excluded.facility_name,
        template_id = excluded.template_id,
        status = excluded.status,
        updated_at = CURRENT_TIMESTAMP`,
    record.id, request.user.id, facilityName, record.templateId, payload, record.status);
    response.json({ ok: true, recordId: record.id });
  } catch (error) { next(error); }
});

app.delete('/api/inspections/:id', authenticated, async (request, response, next) => {
  try {
    if (request.user.role !== 'inspector') return response.status(403).json({ error: 'Only inspectors can delete inspections.' });
    const result = run('DELETE FROM careaudit_inspections WHERE record_id = ? AND inspector_id = ?', request.params.id, request.user.id);
    if (!result.changes) return response.status(404).json({ error: 'Inspection not found.' });
    response.json({ ok: true });
  } catch (error) { next(error); }
});

app.get('/api/inspections/:id/pdf', authenticated, adminOnly, async (request, response, next) => {
  try {
    const row = one('SELECT payload FROM careaudit_inspections WHERE record_id = ? LIMIT 1', request.params.id);
    if (!row) return response.status(404).json({ error: 'Submitted inspection not found.' });
    const record = parsePayload(row.payload);
    const template = checklistTemplates.find((item) => item.id === record.templateId);
    if (!template) return response.status(422).json({ error: 'The source checklist for this inspection is unavailable.' });
    const stats = reportData(record, template);
    const metadata = record.metadata || {};
    const safeName = (record.metadata?.facilityName || 'inspection').replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase() || 'inspection';
    response.setHeader('Content-Type', 'application/pdf');
    response.setHeader('Content-Disposition', `attachment; filename="careaudit-${safeName}.pdf"`);
    const doc = new PDFDocument({ size: 'A4', margin: 42, bufferPages: true });
    doc.pipe(response);
    const colors = {
      ink: '#173533',
      teal: '#0b6b67',
      muted: '#71817d',
      line: '#dce5e0',
      mint: '#edf7f0',
      green: '#43845b',
      gold: '#aa822b',
      red: '#b2604e',
    };
    const pageBottom = () => doc.page.height - doc.page.margins.bottom - 24;
    const ensureSpace = (height) => {
      if (doc.y + height > pageBottom()) doc.addPage();
    };
    const write = (text, options = {}) => {
      doc.font(options.bold ? 'Helvetica-Bold' : 'Helvetica')
        .fontSize(options.size || 9)
        .fillColor(options.color || colors.ink)
        .text(String(text || '—'), options.x === undefined ? doc.page.margins.left : options.x, options.y === undefined ? doc.y : options.y, {
          width: options.width || doc.page.width - doc.page.margins.left - doc.page.margins.right,
          lineGap: options.lineGap === undefined ? 2 : options.lineGap,
          align: options.align || 'left',
        });
    };
    const drawRule = (y, color = colors.line) => {
      doc.moveTo(doc.page.margins.left, y).lineTo(doc.page.width - doc.page.margins.right, y).lineWidth(0.7).strokeColor(color).stroke();
    };
    const sectionHeading = (number, title) => {
      ensureSpace(34);
      const y = doc.y;
      write(number, { x: 42, y, width: 20, size: 8, color: colors.teal, bold: true });
      write(title, { x: 61, y: y - 2, width: 470, size: 15, bold: true });
      doc.y = y + 24;
      drawRule(doc.y);
      doc.y += 12;
    };
    const dateText = (value) => {
      if (!value) return '—';
      const date = new Date(value);
      return Number.isNaN(date.getTime()) ? String(value) : new Intl.DateTimeFormat('en', { month: 'short', day: 'numeric', year: 'numeric' }).format(date);
    };
    const facilityName = metadata.facilityName || 'Untitled facility';
    const address = metadata.facilityAddress
      || [metadata.region, metadata.zone, metadata.woreda, metadata.town, metadata.kebele].filter(Boolean).join(' | ')
      || 'Address not supplied';
    const tone = stats.score >= 85 ? colors.green : stats.score >= 70 ? colors.gold : colors.red;

    write('CareAudit', { x: 42, y: 33, width: 180, size: 18, bold: true, color: colors.teal });
    write('FACILITY COMPLIANCE', { x: 43, y: 54, width: 190, size: 6, color: colors.muted });
    write('FINAL INSPECTION REPORT', { x: 365, y: 42, width: 188, size: 8, color: colors.teal, align: 'right' });
    drawRule(72);

    doc.y = 95;
    write(String(template.title).toUpperCase(), { size: 8, color: colors.teal });
    doc.moveDown(0.45);
    const headingY = doc.y;
    write(facilityName, { y: headingY, width: 400, size: 24, bold: true });
    write(`${address} | ${metadata.inspectionType || 'Inspection'} visit | completed ${dateText(record.completedAt || record.updatedAt)}`, {
      y: doc.y + 2,
      width: 420,
      size: 8,
      color: colors.muted,
    });
    write(`${stats.score}%`, { x: 454, y: headingY - 5, width: 98, size: 28, bold: true, color: tone, align: 'right' });
    write('OVERALL COMPLIANCE', { x: 444, y: headingY + 27, width: 108, size: 6, color: colors.muted, align: 'right' });
    doc.y = Math.max(doc.y, headingY + 43) + 10;
    drawRule(doc.y);
    doc.y += 14;

    const metadataFields = [
      ['Licensed professional', [metadata.professionalName, metadata.profession].filter(Boolean).join(' | ')],
      ['Facility head', metadata.headName],
      ['Owner / operator', metadata.ownerName],
      ['Facility license no. / date', [metadata.licenseNo, metadata.licenseDate].filter(Boolean).join(' | ')],
      ['Valid trade license', metadata.tradeLicenseStatus],
      ['Lead assessor', metadata.assessor],
      ['Phone / P.O. Box', [metadata.contact, metadata.poBox].filter(Boolean).join(' | ')],
      ['Annual patient load', metadata.annualLoad],
      ['House number', metadata.houseNo],
    ];
    const columnWidth = (doc.page.width - doc.page.margins.left - doc.page.margins.right) / 3;
    const metadataY = doc.y;
    metadataFields.forEach(([label, value], index) => {
      const column = index % 3;
      const x = doc.page.margins.left + column * columnWidth;
      const y = metadataY + Math.floor(index / 3) * 39;
      write(String(label).toUpperCase(), { x, y, width: columnWidth - 14, size: 6, color: colors.muted });
      write(value, { x, y: y + 11, width: columnWidth - 14, size: 8, bold: true });
    });
    doc.y = metadataY + 3 * 39 + 6;
    drawRule(doc.y);
    doc.y += 14;

    const calloutY = doc.y;
    doc.roundedRect(42, calloutY, doc.page.width - 84, 42, 6).fill(colors.mint);
    doc.circle(58, calloutY + 21, 7).fill(colors.green);
    const complianceMessage = stats.score >= 85
      ? 'Strong footing with targeted follow-up.'
      : stats.score >= 70
        ? 'Compliant in many areas, with follow-up required.'
        : 'Material gaps require a documented action plan.';
    write(complianceMessage, { x: 74, y: calloutY + 9, width: 455, size: 9, bold: true });
    write(`${stats.critical} critical markers | ${stats.major} major markers | ${stats.unanswered} unanswered requirements`, {
      x: 74,
      y: calloutY + 23,
      width: 455,
      size: 7,
      color: colors.muted,
    });
    doc.y = calloutY + 56;

    sectionHeading('01', 'Section scores');
    stats.sections.forEach((section) => {
      ensureSpace(42);
      const rowY = doc.y;
      write(section.title, { x: 42, y: rowY, width: 230, size: 8, bold: true });
      write(`${section.items.filter((item) => item.response.status).length}/${section.items.length} answered`, {
        x: 42,
        y: rowY + 13,
        width: 230,
        size: 6,
        color: colors.muted,
      });
      const barX = 284;
      const barWidth = 218;
      doc.roundedRect(barX, rowY + 8, barWidth, 4, 2).fill('#edf1ee');
      doc.roundedRect(barX, rowY + 8, Math.max(2, barWidth * section.score / 100), 4, 2).fill(colors.green);
      const sectionTone = section.score >= 85 ? colors.green : section.score >= 70 ? colors.gold : colors.red;
      doc.roundedRect(514, rowY + 1, 38, 22, 10).fill(sectionTone === colors.green ? colors.mint : section.score >= 70 ? '#faf1d5' : '#f8e5e1');
      write(`${section.score}%`, { x: 514, y: rowY + 7, width: 38, size: 7, color: sectionTone, align: 'center', bold: true });
      doc.y = rowY + 32;
      drawRule(doc.y);
      doc.y += 8;
    });

    sectionHeading('02', 'Attention markers');
    if (stats.gaps.length === 0) {
      write('No gaps recorded in this inspection.', { size: 8, color: colors.muted });
      doc.moveDown();
    } else {
      stats.gaps.forEach((item) => {
        const status = stats.statusLabel(item.response.status);
        const titleHeight = doc.heightOfString(item.text, { width: 440, font: 'Helvetica-Bold', fontSize: 8 });
        const detailText = `${item.sectionTitle} | ${status}${item.response.remark ? ` | ${item.response.remark}` : ''}`;
        const detailHeight = doc.heightOfString(detailText, { width: 440, font: 'Helvetica', fontSize: 6 });
        const rowHeight = Math.max(31, titleHeight + detailHeight + 10);
        ensureSpace(rowHeight);
        const y = doc.y;
        const severity = item.severity || 'open';
        const badgeColor = severity === 'critical' ? '#f8e5e1' : '#faf1d5';
        const badgeText = severity === 'critical' ? colors.red : colors.gold;
        doc.roundedRect(42, y + 1, 35, 14, 3).fill(badgeColor);
        write(severity.toUpperCase(), { x: 44, y: y + 5, width: 31, size: 5, bold: true, color: badgeText, align: 'center' });
        write(item.text, { x: 88, y, width: 464, size: 8, bold: true });
        write(detailText, { x: 88, y: y + titleHeight + 4, width: 464, size: 6, color: colors.muted });
        doc.y = y + rowHeight;
        drawRule(doc.y);
        doc.y += 7;
      });
    }

    sectionHeading('03', 'Assessment detail');
    stats.sections.forEach((section) => {
      ensureSpace(30);
      write(section.title, { size: 10, bold: true, color: colors.teal });
      doc.moveDown(0.5);
      section.items.forEach((item) => {
        const responseData = item.response;
        const label = stats.statusLabel(responseData.status);
        const statusColor = ['met', 'available'].includes(responseData.status)
          ? colors.green
          : ['partial', 'na'].includes(responseData.status)
            ? colors.gold
            : ['unmet', 'not-available'].includes(responseData.status)
              ? colors.red
              : colors.muted;
        const itemHeight = doc.heightOfString(item.text, { width: 425, font: 'Helvetica', fontSize: 7 });
        const remarkHeight = responseData.remark
          ? doc.heightOfString(`Remark: ${responseData.remark}`, { width: 425, font: 'Helvetica', fontSize: 6 })
          : 0;
        const rowHeight = Math.max(20, itemHeight + remarkHeight + 9);
        ensureSpace(rowHeight);
        const y = doc.y;
        doc.circle(45, y + 5, 2.5).fill(statusColor);
        write(item.text, { x: 55, y, width: 410, size: 7 });
        write(label, { x: 468, y, width: 84, size: 6, color: statusColor, align: 'right' });
        if (responseData.remark) {
          write(`Remark: ${responseData.remark}`, { x: 55, y: y + itemHeight + 3, width: 410, size: 6, color: colors.muted });
        }
        doc.y = y + rowHeight;
        drawRule(doc.y, '#eef2ef');
        doc.y += 5;
      });
      doc.moveDown(0.6);
    });

    sectionHeading('04', 'Visit notes');
    write(metadata.notes || 'No additional visit note was recorded.', { size: 8 });
    doc.moveDown();
    write(`Process owner: ${metadata.processOwner || '—'}`, { size: 8 });
    write(`Lead assessor: ${metadata.assessor || '—'}`, { size: 8 });
    doc.moveDown();
    write('Inspection team sign-off', { size: 10, bold: true, color: colors.teal });
    doc.moveDown(0.5);
    (record.signatures?.inspectors || []).forEach((inspector, index) => {
      ensureSpace(62);
      write(`Inspector ${index + 1}: ${inspector.name || '—'}`, { size: 8, bold: true });
      const image = signatureImage(inspector.signature);
      if (image) {
        const imageY = doc.y + 3;
        doc.image(image, 48, imageY, { fit: [180, 45] });
        doc.y = imageY + 50;
      } else {
        doc.y += 14;
      }
    });
    ensureSpace(62);
    write(`Pharmacist: ${record.signatures?.pharmacist?.name || '—'}`, { size: 8, bold: true });
    const pharmacistSignature = signatureImage(record.signatures?.pharmacist?.signature);
    if (pharmacistSignature) {
      const imageY = doc.y + 3;
      doc.image(pharmacistSignature, 48, imageY, { fit: [180, 45] });
      doc.y = imageY + 50;
    } else {
      doc.y += 14;
    }
    write(`Date: ${dateText(record.completedAt || record.updatedAt)}`, { size: 7, color: colors.muted });

    const pages = doc.bufferedPageRange();
    for (let index = 0; index < pages.count; index += 1) {
      doc.switchToPage(pages.start + index);
      const footerY = doc.page.height - doc.page.margins.bottom - 12;
      drawRule(footerY);
      write(`CareAudit | Source checklist: ${template.sourceFile}`, { x: 42, y: footerY + 5, width: 390, size: 6, color: colors.muted });
      write(`Page ${index + 1} of ${pages.count}`, { x: 460, y: footerY + 5, width: 92, size: 6, color: colors.muted, align: 'right' });
    }
    doc.end();
  } catch (error) { next(error); }
});

app.get('/api/inspections/:id/export/:format', authenticated, adminOnly, async (request, response, next) => {
  try {
    const format = request.params.format;
    if (!['xlsx', 'docx'].includes(format)) return response.status(400).json({ error: 'Choose an Excel or Word export.' });
    const row = one('SELECT payload FROM careaudit_inspections WHERE record_id = ? LIMIT 1', request.params.id);
    if (!row) return response.status(404).json({ error: 'Submitted inspection not found.' });
    const record = parsePayload(row.payload);
    const template = checklistTemplates.find((item) => item.id === record.templateId);
    if (!template) return response.status(422).json({ error: 'The source checklist for this inspection is unavailable.' });

    const stats = reportData(record, template);
    const metadata = record.metadata || {};
    const completedAt = record.completedAt || record.updatedAt || '—';
    const safeName = (metadata.facilityName || 'inspection').replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase() || 'inspection';
    const reportTitle = metadata.facilityName || 'Untitled facility';
    const detailRows = stats.sections.flatMap((section) => section.items.map((item) => [
      section.title,
      item.text,
      stats.statusLabel(item.response.status),
      item.severity || '—',
      item.response.remark || '—',
    ]));
    const metadataRows = [
      ['Facility', reportTitle],
      ['Checklist', template.title],
      ['Inspection type', metadata.inspectionType || 'Inspection'],
      ['Completed', completedAt],
      ['Facility address', metadata.facilityAddress || '—'],
      ['Location', [metadata.region, metadata.zone, metadata.woreda, metadata.town, metadata.kebele, metadata.houseNo].filter(Boolean).join(' · ') || '—'],
      ['Licensed professional', [metadata.professionalName, metadata.profession].filter(Boolean).join(' · ') || '—'],
      ['Facility head', metadata.headName || '—'],
      ['Owner / operator', metadata.ownerName || '—'],
      ['Facility license no. / date', [metadata.licenseNo, metadata.licenseDate].filter(Boolean).join(' · ') || '—'],
      ['Valid trade license', metadata.tradeLicenseStatus || 'Not recorded'],
      ['Phone / P.O. Box', [metadata.contact, metadata.poBox].filter(Boolean).join(' · ') || '—'],
      ['Annual patient load', metadata.annualLoad || '—'],
      ['Lead assessor', metadata.assessor || '—'],
      ['Process owner', metadata.processOwner || '—'],
      ['Visit notes', metadata.notes || 'No additional visit note was recorded.'],
      ['Inspectors', (record.signatures?.inspectors || []).map((inspector) => inspector.name).filter(Boolean).join(', ') || '—'],
      ['Pharmacist', record.signatures?.pharmacist?.name || '—'],
    ];

    if (format === 'xlsx') {
      const workbook = new ExcelJS.Workbook();
      workbook.creator = 'CareAudit';
      workbook.created = new Date();
      const summary = workbook.addWorksheet('Report summary');
      summary.columns = [
        { key: 'field', width: 36 },
        { key: 'value', width: 68 },
        { key: 'details', width: 34 },
      ];
      summary.addRow(['CareAudit | Final inspection report', '', '']);
      summary.mergeCells('A1:C1');
      summary.addRow(['Facility', reportTitle, '']);
      summary.addRow(['Checklist', template.title, '']);
      summary.addRow(['Inspection type', metadata.inspectionType || 'Inspection', '']);
      summary.addRow(['Completed', completedAt, '']);
      summary.addRow([]);
      summary.addRow(['OVERALL COMPLIANCE', `${stats.score}%`, '']);
      summary.addRow(['Critical markers', stats.critical, '']);
      summary.addRow(['Major markers', stats.major, '']);
      summary.addRow(['Unanswered requirements', stats.unanswered, '']);
      summary.addRow([]);
      summary.addRow(['FACILITY INFORMATION', 'Value', '']);
      metadataRows.slice(4, 15).forEach(([field, value]) => summary.addRow([field, value, '']));
      metadataRows.slice(15).forEach(([field, value]) => summary.addRow([field, value, '']));
      summary.addRow([]);
      summary.addRow(['SECTION SCORES', 'Score', 'Answered']);
      stats.sections.forEach((section) => {
        summary.addRow([
          section.title,
          `${section.score}%`,
          `${section.items.filter((item) => item.response.status).length}/${section.items.length}`,
        ]);
      });
      summary.eachRow((line, rowNumber) => {
        line.eachCell((cell) => {
          cell.alignment = { vertical: 'top', wrapText: true };
          if ([1, 12, 28].includes(rowNumber)) {
            cell.font = { bold: true, color: { argb: 'FF0B6B67' } };
          }
          if (rowNumber === 7) cell.font = { bold: true, size: 14, color: { argb: 'FF0B6B67' } };
        });
      });
      summary.getRow(1).font = { bold: true, size: 16, color: { argb: 'FFFFFFFF' } };
      summary.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF0B6B67' } };
      [12, 28].forEach((rowNumber) => {
        summary.getRow(rowNumber).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFEAF4ED' } };
      });
      summary.views = [{ state: 'frozen', ySplit: 1 }];

      const details = workbook.addWorksheet('Assessment detail');
      details.columns = [
        { header: 'Checklist section', key: 'section', width: 38 },
        { header: 'Requirement', key: 'requirement', width: 90 },
        { header: 'Response', key: 'response', width: 22 },
        { header: 'Severity', key: 'severity', width: 16 },
        { header: 'Inspector remark', key: 'remark', width: 60 },
      ];
      detailRows.forEach((values) => details.addRow(values));
      details.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } };
      details.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF0B6B67' } };
      details.getRow(1).alignment = { vertical: 'middle', wrapText: true };
      details.eachRow((line) => line.eachCell((cell) => {
        cell.alignment = { vertical: 'top', wrapText: true };
      }));
      details.views = [{ state: 'frozen', ySplit: 1 }];
      details.autoFilter = { from: 'A1', to: 'E1' };

      const attention = workbook.addWorksheet('Attention markers');
      attention.columns = [
        { header: 'Severity', key: 'severity', width: 16 },
        { header: 'Checklist section', key: 'section', width: 38 },
        { header: 'Requirement', key: 'requirement', width: 80 },
        { header: 'Response', key: 'response', width: 22 },
        { header: 'Inspector remark', key: 'remark', width: 60 },
      ];
      const attentionRows = stats.gaps.map((item) => [
        item.severity || 'Open',
        item.sectionTitle,
        item.text,
        stats.statusLabel(item.response.status),
        item.response.remark || '—',
      ]);
      if (attentionRows.length) attentionRows.forEach((values) => attention.addRow(values));
      else attention.addRow(['None', 'No gaps recorded in this inspection.', '—', '—', '—']);
      attention.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } };
      attention.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF0B6B67' } };
      attention.eachRow((line) => line.eachCell((cell) => {
        cell.alignment = { vertical: 'top', wrapText: true };
      }));
      attention.views = [{ state: 'frozen', ySplit: 1 }];
      attention.autoFilter = { from: 'A1', to: 'E1' };
      workbook.views = [{ activeTab: 0 }];

      const buffer = await workbook.xlsx.writeBuffer();
      response.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      response.setHeader('Content-Disposition', `attachment; filename="careaudit-${safeName}.xlsx"`);
      return response.send(Buffer.from(buffer));
    }

    const paragraph = (text, options = {}) => new Paragraph({
      children: [new TextRun({
        text: String(text ?? '—'),
        font: 'Aptos',
        size: options.size || 20,
        bold: Boolean(options.bold),
        color: options.color || '173533',
      })],
      heading: options.heading,
      spacing: { before: options.before || 0, after: options.after === undefined ? 100 : options.after },
    });
    const heading = (text, level = HeadingLevel.HEADING_2) => paragraph(text, {
      heading: level,
      bold: true,
      color: '0B6B67',
      size: level === HeadingLevel.HEADING_1 ? 32 : 24,
      before: level === HeadingLevel.HEADING_1 ? 220 : 300,
      after: 120,
    });
    const makeTable = (headers, rows, widths) => {
      const border = { style: BorderStyle.SINGLE, size: 4, color: 'DCE5E0' };
      const cell = (value, header, width) => new TableCell({
        children: [paragraph(value, { bold: header, color: header ? 'FFFFFF' : '173533', size: 18, after: 0 })],
        width: { size: width, type: WidthType.DXA },
        margins: { top: 90, bottom: 90, left: 100, right: 100 },
        ...(header ? { shading: { type: ShadingType.CLEAR, fill: '0B6B67' } } : {}),
        borders: { top: border, bottom: border, left: border, right: border },
      });
      const tableRows = [
        new TableRow({ children: headers.map((value, index) => cell(value, true, widths[index])) }),
        ...rows.map((values) => new TableRow({ children: values.map((value, index) => cell(value, false, widths[index])) })),
      ];
      return new Table({
        rows: tableRows,
        width: { size: widths.reduce((sum, width) => sum + width, 0), type: WidthType.DXA },
        columnWidths: widths,
      });
    };
    const children = [
      paragraph('CareAudit', { heading: HeadingLevel.TITLE, bold: true, color: '0B6B67', size: 36, after: 50 }),
      paragraph('FACILITY COMPLIANCE  |  FINAL INSPECTION REPORT', { size: 16, color: '71817D', after: 240 }),
      heading(reportTitle, HeadingLevel.HEADING_1),
      paragraph(`${template.title} | ${metadata.inspectionType || 'Inspection'} visit | completed ${completedAt}`, { size: 18, color: '71817D', after: 220 }),
      paragraph(`OVERALL COMPLIANCE: ${stats.score}%`, { bold: true, color: stats.score >= 85 ? '43845B' : stats.score >= 70 ? 'AA822B' : 'B2604E', size: 28, after: 100 }),
      paragraph(`${stats.critical} critical markers | ${stats.major} major markers | ${stats.unanswered} unanswered requirements`, { size: 18, color: '71817D' }),
      heading('Facility information'),
      makeTable(['Report field', 'Value'], metadataRows, [2800, 6570]),
      heading('Section scores'),
      makeTable(
        ['Checklist section', 'Score', 'Answered'],
        stats.sections.map((section) => [
          section.title,
          `${section.score}%`,
          `${section.items.filter((item) => item.response.status).length}/${section.items.length}`,
        ]),
        [5800, 1500, 2070],
      ),
      heading('Attention markers'),
      ...(stats.gaps.length
        ? [makeTable(
          ['Severity', 'Checklist section', 'Requirement', 'Response / remark'],
          stats.gaps.map((item) => [
            item.severity || 'Open',
            item.sectionTitle,
            item.text,
            `${stats.statusLabel(item.response.status)}${item.response.remark ? ` | ${item.response.remark}` : ''}`,
          ]),
          [1200, 2300, 3900, 1970],
        )]
        : [paragraph('No gaps recorded in this inspection.')]),
      heading('Assessment detail'),
      ...stats.sections.flatMap((section) => [
        heading(section.title, HeadingLevel.HEADING_3),
        makeTable(
          ['Requirement', 'Response', 'Severity', 'Inspector remark'],
          section.items.map((item) => [
            item.text,
            stats.statusLabel(item.response.status),
            item.severity || '—',
            item.response.remark || '—',
          ]),
          [4860, 1450, 1050, 2010],
        ),
      ]),
      heading('Visit notes'),
      paragraph(metadata.notes || 'No additional visit note was recorded.'),
      heading('Inspection team sign-off'),
      makeTable(
        ['Role', 'Name'],
        [
          ...(record.signatures?.inspectors || []).map((inspector, index) => [`Inspector ${index + 1}`, inspector.name || '—']),
          ['Pharmacist', record.signatures?.pharmacist?.name || '—'],
          ['Lead assessor', metadata.assessor || '—'],
          ['Process owner', metadata.processOwner || '—'],
        ],
        [2800, 6570],
      ),
      paragraph(`Source checklist: ${template.sourceFile}`, { size: 16, color: '71817D', before: 240 }),
      paragraph(`Generated by CareAudit admin review | ${new Date().toISOString()}`, { size: 14, color: '71817D' }),
    ];
    const document = new Document({
      creator: 'CareAudit',
      title: `CareAudit inspection report - ${reportTitle}`,
      description: `${template.title} inspection report`,
      sections: [{
        properties: { page: { margin: { top: 720, right: 720, bottom: 720, left: 720 } } },
        children,
      }],
    });
    const buffer = await Packer.toBuffer(document);
    response.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    response.setHeader('Content-Disposition', `attachment; filename="careaudit-${safeName}.docx"`);
    return response.send(buffer);
  } catch (error) { next(error); }
});

app.post('/api/inspections/submit', authenticated, async (request, response, next) => {
  try {
    if (request.user.role !== 'inspector') return response.status(403).json({ error: 'Only inspectors can submit inspections.' });
    const record = request.body?.record;
    if (!record?.id || !record?.templateId || !record?.metadata?.facilityName || record.status !== 'completed') {
      return response.status(400).json({ error: 'A completed inspection with a facility name is required.' });
    }
    const inspectors = record.signatures?.inspectors;
    if (!Array.isArray(inspectors) || !completeSigner(inspectors[0]) || !completeSigner(record.signatures?.pharmacist)) {
      return response.status(400).json({ error: 'One inspector name and drawn signature, plus the pharmacist name and drawn signature, are required.' });
    }
    const payload = JSON.stringify({ ...record, status: 'completed' });
    const existing = one('SELECT inspector_id FROM careaudit_inspections WHERE record_id = ? LIMIT 1', record.id);
    if (existing && existing.inspector_id !== request.user.id) return response.status(403).json({ error: 'This inspection belongs to another inspector.' });
    run(`INSERT INTO careaudit_inspections (record_id, inspector_id, facility_name, template_id, payload, status, submitted_at)
      VALUES (?, ?, ?, ?, ?, 'completed', CURRENT_TIMESTAMP)
      ON CONFLICT(record_id) DO UPDATE SET payload = excluded.payload, facility_name = excluded.facility_name, template_id = excluded.template_id, status = 'completed', submitted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP`,
    record.id, request.user.id, record.metadata.facilityName.trim(), record.templateId, payload);
    response.status(201).json({ ok: true, recordId: record.id });
  } catch (error) { next(error); }
});

const distRoot = path.join(projectRoot, 'frontend', 'dist');
if (fs.existsSync(distRoot)) {
  app.use(express.static(distRoot, { index: 'index.html' }));
  app.use((request, response, next) => {
    if (request.method === 'GET' && request.accepts('html')) return response.sendFile(path.join(distRoot, 'index.html'));
    return next();
  });
}

app.use((error, _request, response, _next) => {
  console.error(error);
  response.status(500).json({ error: 'Server error.' });
});

async function start() {
  await ensureSchema();
  app.listen(port, '0.0.0.0', () => console.log(`CareAudit server listening on ${port}`));
}

start().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
 