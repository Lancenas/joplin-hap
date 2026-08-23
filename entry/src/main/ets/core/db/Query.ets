// Thin RdbStore wrapper providing typed query helpers and a small value binder.
import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { getStore } from './Database';

export type Row = Record<string, string | number | null>;

export async function queryAll(
  sql: string,
  bind?: relationalStore.ValueType[]
): Promise<Row[]> {
  const store = await getStore();
  const rs = await store.querySql(sql, bind ?? []);
  const rows: Row[] = [];
  const cols = rs.columnNames;
  while (rs.goToNextRow()) {
    const row: Row = {};
    for (let i = 0; i < cols.length; i++) {
      const name = cols[i];
      row[name] = readValue(rs, i);
    }
    rows.push(row);
  }
  rs.close();
  return rows;
}

export async function queryOne(
  sql: string,
  bind?: relationalStore.ValueType[]
): Promise<Row | null> {
  const store = await getStore();
  const rs = await store.querySql(sql, bind ?? []);
  let row: Row | null = null;
  if (rs.goToNextRow()) {
    const obj: Row = {};
    const cols = rs.columnNames;
    for (let i = 0; i < cols.length; i++) {
      obj[cols[i]] = readValue(rs, i);
    }
    row = obj;
  }
  rs.close();
  return row;
}

export async function exec(
  sql: string,
  bind?: relationalStore.ValueType[]
): Promise<void> {
  const store = await getStore();
  try {
    await store.executeSql(sql, bind ?? []);
  } catch (e) {
    // 把失败的具体 SQL 附进错误消息，否则 HarmonyOS 只给一句
    // "Generic error: Insert failed or the updated data does not exist"，
    // 根本无法定位是哪条语句。
    const be: BusinessError = e as BusinessError;
    const snippet: string = sql.replace(/\s+/g, ' ').slice(0, 90);
    console.error(`[db] exec failed: ${be.code} ${be.message} | SQL: ${snippet}`);
    throw new Error(`SQLite[${be.code}] ${be.message} | SQL: ${snippet}`);
  }
}

export async function transaction(fn: () => Promise<void>): Promise<void> {
  const store = await getStore();
  await store.beginTransaction();
  try {
    await fn();
    await store.commit();
  } catch (e) {
    await store.rollBack();
    throw e as Error;
  }
}

function readValue(rs: relationalStore.ResultSet, idx: number): string | number | null {
  // relationalStore does not expose a "type tag" on ResultSet columns in the
  // public API; we sniff the value based on its runtime type.
  try {
    const v = rs.getValue(idx);
    if (v === null || v === undefined) {
      return null;
    }
    if (typeof v === 'string') {
      return v;
    }
    if (typeof v === 'number') {
      return v;
    }
    return v.toString();
  } catch (_) {
    try {
      const n = rs.getLong(idx);
      if (Number.isNaN(n)) {
        return null;
      }
      return n;
    } catch (_) {
      return null;
    }
  }
}
