// Joplin-compatible SQLite schema. Mirrors packages/lib/JoplinDatabase.ts so
// data exported by the official Joplin clients can be imported directly.
import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

const DB_NAME = 'joplin.db';
const SECURITY_LEVEL = relationalStore.SecurityLevel.S1;
const STORE_CONFIG: relationalStore.StoreConfig = {
  name: DB_NAME,
  securityLevel: SECURITY_LEVEL,
};

const SCHEMA_STATEMENTS: string[] = [
  `CREATE TABLE IF NOT EXISTS folders (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL DEFAULT '',
    parent_id TEXT NOT NULL DEFAULT '',
    created_time INT NOT NULL,
    updated_time INT NOT NULL,
    user_created_time INT NOT NULL,
    user_updated_time INT NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS folders_title ON folders (title)`,
  `CREATE INDEX IF NOT EXISTS folders_updated_time ON folders (updated_time)`,

  `CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY,
    parent_id TEXT NOT NULL DEFAULT '',
    title TEXT NOT NULL DEFAULT '',
    body TEXT NOT NULL DEFAULT '',
    created_time INT NOT NULL,
    updated_time INT NOT NULL,
    is_conflict INT NOT NULL DEFAULT 0,
    latitude NUMERIC NOT NULL DEFAULT 0,
    longitude NUMERIC NOT NULL DEFAULT 0,
    altitude NUMERIC NOT NULL DEFAULT 0,
    author TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT '',
    is_todo INT NOT NULL DEFAULT 0,
    todo_due INT NOT NULL DEFAULT 0,
    todo_completed INT NOT NULL DEFAULT 0,
    source TEXT NOT NULL DEFAULT '',
    source_application TEXT NOT NULL DEFAULT '',
    application_data TEXT NOT NULL DEFAULT '',
    \`order\` INT NOT NULL DEFAULT 0,
    user_created_time INT NOT NULL,
    user_updated_time INT NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS notes_title ON notes (title)`,
  `CREATE INDEX IF NOT EXISTS notes_updated_time ON notes (updated_time)`,
  `CREATE INDEX IF NOT EXISTS notes_parent_id ON notes (parent_id)`,
  `CREATE INDEX IF NOT EXISTS notes_is_conflict ON notes (is_conflict)`,
  `CREATE INDEX IF NOT EXISTS notes_is_todo ON notes (is_todo)`,
  `CREATE INDEX IF NOT EXISTS notes_order ON notes (\`order\`)`,

  `CREATE TABLE IF NOT EXISTS tags (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL DEFAULT '',
    parent_id TEXT NOT NULL DEFAULT '',
    created_time INT NOT NULL,
    updated_time INT NOT NULL,
    user_created_time INT NOT NULL,
    user_updated_time INT NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS tags_title ON tags (title)`,

  `CREATE TABLE IF NOT EXISTS note_tags (
    id TEXT PRIMARY KEY,
    note_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    created_time INT NOT NULL,
    updated_time INT NOT NULL,
    user_created_time INT NOT NULL,
    user_updated_time INT NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS note_tags_note_id ON note_tags (note_id)`,
  `CREATE INDEX IF NOT EXISTS note_tags_tag_id ON note_tags (tag_id)`,

  `CREATE TABLE IF NOT EXISTS resources (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL DEFAULT '',
    mime TEXT NOT NULL,
    filename TEXT NOT NULL DEFAULT '',
    file_extension TEXT NOT NULL DEFAULT '',
    size INT NOT NULL DEFAULT 0,
    created_time INT NOT NULL,
    updated_time INT NOT NULL,
    user_created_time INT NOT NULL,
    user_updated_time INT NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS resources_updated_time ON resources (updated_time)`,

  `CREATE TABLE IF NOT EXISTS settings (
    \`key\` TEXT PRIMARY KEY,
    \`value\` TEXT,
    \`type\` INT NOT NULL
  )`,

  `CREATE TABLE IF NOT EXISTS sync_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_target INT NOT NULL,
    sync_time INT NOT NULL DEFAULT 0,
    item_type INT NOT NULL,
    item_id TEXT NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS sync_items_sync_time ON sync_items (sync_time)`,
  `CREATE INDEX IF NOT EXISTS sync_items_item_id ON sync_items (item_id)`,

  `CREATE TABLE IF NOT EXISTS deleted_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_type INT NOT NULL,
    item_id TEXT NOT NULL,
    deleted_time INT NOT NULL
  )`,

  `CREATE TABLE IF NOT EXISTS note_fts (
    rowid INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    body TEXT NOT NULL
  )`,
  `CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
     INSERT INTO note_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
   END`,
  `CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
     DELETE FROM note_fts WHERE rowid = old.rowid;
   END`,
  `CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
     DELETE FROM note_fts WHERE rowid = old.rowid;
     INSERT INTO note_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
   END`,

  `CREATE TABLE IF NOT EXISTS schema_meta (
    \`key\` TEXT PRIMARY KEY,
    \`value\` TEXT NOT NULL
  )`
];

const SCHEMA_VERSION = '1';

let storeInstance: relationalStore.RdbStore | null = null;
let initPromise: Promise<relationalStore.RdbStore> | null = null;

// EntryAbility hands us its context at startup. ArkTS forbids casting
// `globalThis` to an indexed type, so we keep it in a module-scoped variable.
let appContext: Context | null = null;

export function bindAppContext(ctx: Context): void {
  appContext = ctx;
}

function resolveContext(): Context {
  if (appContext === null) {
    throw new Error('App context not bound — call bindAppContext() from EntryAbility.onCreate');
  }
  return appContext;
}

async function readSchemaVersion(store: relationalStore.RdbStore): Promise<string> {
  try {
    const rs = await store.querySql('SELECT `value` FROM schema_meta WHERE `key` = ?', ['version']);
    let stored: string = '';
    if (rs.goToFirstRow()) {
      stored = rs.getString(0);
    }
    rs.close();
    return stored;
  } catch (err) {
    // Table does not exist yet on a fresh install.
    return '';
  }
}

async function runMigrations(store: relationalStore.RdbStore): Promise<void> {
  const stored: string = await readSchemaVersion(store);
  if (stored === SCHEMA_VERSION) {
    return;
  }
  for (const stmt of SCHEMA_STATEMENTS) {
    try {
      await store.executeSql(stmt);
    } catch (err) {
      // CREATE INDEX / TRIGGER raise benign errors when an object already
      // exists; we ignore the duplicate-object codes from relationalStore.
      const be: BusinessError = err as BusinessError;
      const code: number = be.code;
      if (code !== 14800023 && code !== 14800031) {
        throw err as Error;
      }
    }
  }
  await store.executeSql(
    'INSERT OR REPLACE INTO schema_meta (`key`, `value`) VALUES (?, ?)',
    ['version', SCHEMA_VERSION]
  );
}

export async function getStore(): Promise<relationalStore.RdbStore> {
  if (storeInstance !== null) {
    return storeInstance;
  }
  if (initPromise === null) {
    initPromise = openStore();
  }
  return initPromise;
}

async function openStore(): Promise<relationalStore.RdbStore> {
  const store = await relationalStore.getRdbStore(resolveContext(), STORE_CONFIG);
  await runMigrations(store);
  storeInstance = store;
  return store;
}
