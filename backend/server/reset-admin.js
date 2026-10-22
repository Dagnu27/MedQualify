import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { emitKeypressEvents } from 'node:readline';
import { fileURLToPath } from 'node:url';
import bcrypt from 'bcryptjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const databasePath = path.resolve(process.env.DATABASE_PATH || path.join(__dirname, 'data', 'careaudit.sqlite'));

function readHidden(prompt) {
  if (!process.stdin.isTTY || typeof process.stdin.setRawMode !== 'function') {
    throw new Error('Run this command in an interactive terminal so your password can be entered privately.');
  }

  return new Promise((resolve, reject) => {
    emitKeypressEvents(process.stdin);
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdout.write(prompt);
    let value = '';

    const cleanup = () => {
      process.stdin.removeListener('keypress', onKeypress);
      process.stdin.setRawMode(false);
      process.stdin.pause();
    };
    const onKeypress = (character, key = {}) => {
      if (key.ctrl && key.name === 'c') {
        cleanup();
        process.stdout.write('\n');
        reject(new Error('Password reset cancelled.'));
      } else if (key.name === 'return' || key.name === 'enter') {
        cleanup();
        process.stdout.write('\n');
        resolve(value);
      } else if (key.name === 'backspace') {
        value = value.slice(0, -1);
      } else if (character && !key.ctrl && !key.meta) {
        value += character;
      }
    };

    process.stdin.on('keypress', onKeypress);
  });
}

async function main() {
  const password = await readHidden('New admin password (6-200 characters): ');
  if (password.length < 6 || password.length > 200) {
    throw new Error('Password must be between 6 and 200 characters.');
  }

  const confirmation = await readHidden('Confirm new admin password: ');
  if (password !== confirmation) {
    throw new Error('Passwords do not match. No changes were made.');
  }

  if (!fs.existsSync(databasePath)) {
    throw new Error(`Database not found at ${databasePath}. Start the app once to initialize it.`);
  }

  const db = new DatabaseSync(databasePath);
  db.exec('PRAGMA foreign_keys = ON');
  try {
    const admin = db.prepare("SELECT id, username FROM careaudit_users WHERE role = 'admin' LIMIT 1").get();
    if (!admin) throw new Error('No admin account exists in the database.');

    const passwordHash = await bcrypt.hash(password, 12);
    db.exec('BEGIN IMMEDIATE');
    try {
      db.prepare('UPDATE careaudit_users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(passwordHash, admin.id);
      db.prepare('DELETE FROM careaudit_sessions WHERE user_id = ?').run(admin.id);
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }

    console.log(`Admin password reset successfully for "${admin.username}". Sign in with your new password.`);
  } finally {
    db.close();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
