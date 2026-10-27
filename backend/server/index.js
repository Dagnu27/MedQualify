import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import express from 'express';
import bcrypt from 'bcryptjs';
import PDFDocument from 'pdfkit';

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
    submitted_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (inspector_id) REFERENCES careaudit_users(id) ON DELETE CASCADE
  );
  CREATE INDEX IF NOT EXISTS idx_careaudit_inspections_inspector ON careaudit_inspections(inspector_id);
  CREATE INDEX IF NOT EXISTS idx_careaudit_inspections_submitted ON careaudit_inspections(submitted_at);`);
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
      ? all(`SELECT i.record_id, i.payload, i.submitted_at, u.name AS inspector_name
        FROM careaudit_inspections i
        JOIN careaudit_users u ON u.id = i.inspector_id
        ORDER BY i.submitted_at DESC`)
      : all(`SELECT i.record_id, i.payload, i.submitted_at, u.name AS inspector_name
        FROM careaudit_inspections i
        JOIN careaudit_users u ON u.id = i.inspector_id
        WHERE i.inspector_id = ?
        ORDER BY i.submitted_at DESC`, request.user.id);
    const inspections = rows.map((row) => ({
      ...parsePayload(row.payload),
      id: row.record_id,
      status: 'completed',
      submittedAt: row.submitted_at,
      inspectorName: row.inspector_name,
    }));
    response.json({ inspections });
  } catch (error) { next(error); }
});

app.get('/api/inspections/:id/pdf', authenticated, adminOnly, async (request, response, next) => {
  try {
    const row = one('SELECT payload FROM careaudit_inspections WHERE record_id = ? LIMIT 1', request.params.id);
    if (!row) return response.status(404).json({ error: 'Submitted inspection not found.' });
    const record = parsePayload(row.payload);
    const template = checklistTemplates.find((item) => item.id === record.templateId);
    if (!template) return response.status(422).json({ error: 'The source checklist for this inspection is unavailable.' });
    const responses = record.responses || {};
    const allItems = template.sections.flatMap((section) => section.items);
    const scoreFor = (item) => {
      const status = responses[item.id]?.status;
      return status === 'met' || status === 'available' ? 1 : status === 'partial' ? 0.5 : 0;
    };
    const eligible = allItems.filter((item) => item.scored !== false && (!item.optional || (responses[item.id]?.status && responses[item.id].status !== 'na')));
    const score = eligible.length ? Math.round((eligible.reduce((sum, item) => sum + scoreFor(item), 0) / eligible.length) * 100) : 0;
    const label = (status) => ({ met: 'Met', partial: 'Partially met', unmet: 'Unmet', available: 'Available', 'not-available': 'Not available', na: 'Not applicable' }[status] || 'Not assessed');
    const safeName = (record.metadata?.facilityName || 'inspection').replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase() || 'inspection';
    response.setHeader('Content-Type', 'application/pdf');
    response.setHeader('Content-Disposition', `attachment; filename="careaudit-${safeName}.pdf"`);
    const doc = new PDFDocument({ size: 'A4', margin: 48, bufferPages: true });
    doc.pipe(response);
    const line = (text, size = 9, options = {}) => {
      if (doc.y > 750) doc.addPage();
      doc.font(options.bold ? 'Helvetica-Bold' : 'Helvetica').fontSize(size).fillColor(options.color || '#173533').text(String(text || '—'), { width: 500, lineGap: 2 });
    };
    line('CareAudit', 22, { bold: true, color: '#0b6b67' });
    line('FINAL INSPECTION REPORT', 9, { bold: true, color: '#5f7270' });
    doc.moveDown(.8);
    line(record.metadata?.facilityName || 'Untitled facility', 20, { bold: true });
    line(`${template.title} · ${record.metadata?.inspectionType || 'Inspection'} visit`, 10, { color: '#5f7270' });
    line(`Completed ${record.completedAt || record.updatedAt || new Date().toISOString()}`, 9, { color: '#5f7270' });
    doc.moveDown(.6);
    line(`OVERALL COMPLIANCE: ${score}%`, 14, { bold: true, color: score >= 85 ? '#34734f' : score >= 70 ? '#927427' : '#a85949' });
    line(`Facility address: ${record.metadata?.facilityAddress || '—'}`);
    line(`Location: ${[record.metadata?.region, record.metadata?.zone, record.metadata?.woreda, record.metadata?.town, record.metadata?.kebele, record.metadata?.houseNo].filter(Boolean).join(' · ') || '—'}`);
    line(`Licensed professional: ${[record.metadata?.professionalName, record.metadata?.profession].filter(Boolean).join(' · ') || '—'}`);
    line(`Facility head: ${record.metadata?.headName || '—'}   Owner / operator: ${record.metadata?.ownerName || '—'}`);
    line(`Facility license: ${record.metadata?.licenseNo || '—'}   Date: ${record.metadata?.licenseDate || '—'}`);
    line(`Valid trade license: ${record.metadata?.tradeLicenseStatus || 'Not recorded'}`);
    line(`Phone: ${record.metadata?.contact || '—'}   P.O. Box: ${record.metadata?.poBox || '—'}`);
    line(`Lead assessor: ${record.metadata?.assessor || '—'}`);
    doc.moveDown(.7);
    template.sections.forEach((section, sectionIndex) => {
      const sectionItems = section.items;
      const sectionEligible = sectionItems.filter((item) => item.scored !== false && (!item.optional || (responses[item.id]?.status && responses[item.id].status !== 'na')));
      const sectionScore = sectionEligible.length ? Math.round((sectionEligible.reduce((sum, item) => sum + scoreFor(item), 0) / sectionEligible.length) * 100) : 0;
      line(`${String(sectionIndex + 1).padStart(2, '0')} · ${section.title} — ${sectionScore}%`, 12, { bold: true, color: '#0b6b67' });
      sectionItems.forEach((item) => {
        const responseData = responses[item.id] || {};
        line(`${label(responseData.status)}${item.severity ? ` · ${item.severity}` : ''} — ${item.text}`, 8.5, { color: responseData.status === 'unmet' || responseData.status === 'not-available' ? '#a85949' : '#173533' });
        if (responseData.remark) line(`Remark: ${responseData.remark}`, 8, { color: '#5f7270' });
      });
      doc.moveDown(.5);
    });
    line('Visit notes', 12, { bold: true, color: '#0b6b67' });
    line(record.metadata?.notes || 'No additional visit note was recorded.');
    doc.moveDown(1);
    line(`Process owner: ${record.metadata?.processOwner || '—'}`);
    line(`Lead assessor: ${record.metadata?.assessor || '—'}`);
    line('Inspection team sign-off', 12, { bold: true, color: '#0b6b67' });
    (record.signatures?.inspectors || []).forEach((inspector, index) => {
      if (doc.y > 690) doc.addPage();
      line(`Inspector ${index + 1}: ${inspector.name || '—'}`, 9, { bold: true });
      const image = signatureImage(inspector.signature);
      if (image) {
        const imageY = doc.y + 3;
        doc.image(image, 48, imageY, { fit: [180, 45] });
        doc.y = imageY + 50;
      }
    });
    if (doc.y > 690) doc.addPage();
    line(`Pharmacist: ${record.signatures?.pharmacist?.name || '—'}`, 9, { bold: true });
    const pharmacistSignature = signatureImage(record.signatures?.pharmacist?.signature);
    if (pharmacistSignature) {
      const imageY = doc.y + 3;
      doc.image(pharmacistSignature, 48, imageY, { fit: [180, 45] });
      doc.y = imageY + 50;
    }
    line(`Date: ${record.completedAt || record.updatedAt || '____________________________'}`);
    doc.moveDown(1);
    line(`Generated by CareAudit admin review · ${new Date().toISOString()}`, 8, { color: '#5f7270' });
    doc.end();
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
    if (!Array.isArray(inspectors) || inspectors.length < 3 || !inspectors.every(completeSigner) || !completeSigner(record.signatures?.pharmacist)) {
      return response.status(400).json({ error: 'At least three inspector names and drawn signatures, plus the pharmacist name and drawn signature, are required.' });
    }
    const payload = JSON.stringify({ ...record, status: 'completed' });
    const existing = one('SELECT inspector_id FROM careaudit_inspections WHERE record_id = ? LIMIT 1', record.id);
    if (existing && existing.inspector_id !== request.user.id) return response.status(403).json({ error: 'This inspection belongs to another inspector.' });
    run(`INSERT INTO careaudit_inspections (record_id, inspector_id, facility_name, template_id, payload, submitted_at)
      VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
      ON CONFLICT(record_id) DO UPDATE SET payload = excluded.payload, facility_name = excluded.facility_name, template_id = excluded.template_id, submitted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP`,
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
 