import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { SqlConnection, SqlRow, SqlValue } from './SqlDatabase';

export class NativeSqlConnection implements SqlConnection {
  private store: relationalStore.RdbStore;
  private transaction: relationalStore.Transaction | null = null;

  constructor(store: relationalStore.RdbStore) { this.store = store; }

  static async open(context: common.Context, name: string = 'lifegraph.db'): Promise<NativeSqlConnection> {
    const config: relationalStore.StoreConfig = {
      name: name, securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    return new NativeSqlConnection(store);
  }

  async query(sql: string, values: SqlValue[] = []): Promise<SqlRow[]> {
    const result = this.transaction !== null ? await this.transaction.querySql(sql, values) : await this.store.querySql(sql, values);
    const rows: SqlRow[] = [];
    try {
      const names = result.columnNames;
      while (result.goToNextRow()) {
        const row = new SqlRow();
        for (let i = 0; i < names.length; i++) {
          if (result.isColumnNull(i)) { row.values.set(names[i], null); }
          else {
            const value = result.getValue(i);
            if (typeof value === 'string' || typeof value === 'number') { row.values.set(names[i], value); }
          }
        }
        rows.push(row);
      }
    } finally { result.close(); }
    return rows;
  }

  async execute(sql: string, values: SqlValue[] = []): Promise<void> {
    if (this.transaction !== null) { await this.transaction.execute(sql, values); }
    else { await this.store.executeSql(sql, values); }
  }
  async begin(): Promise<void> { this.transaction = await this.store.createTransaction(); }
  async commit(): Promise<void> {
    if (this.transaction === null) { throw new Error('没有可提交的事务'); }
    await this.transaction.commit(); this.transaction = null;
  }
  async rollback(): Promise<void> {
    if (this.transaction !== null) { await this.transaction.rollback(); this.transaction = null; }
  }
  async close(): Promise<void> { await this.store.close(); }
  getVersion(): number { return this.store.version; }
  setVersion(version: number): void {
    if (!Number.isInteger(version) || version < 0) { throw new Error('无效数据版本'); }
    if (this.transaction !== null) { this.transaction.executeSync('PRAGMA user_version = ' + version.toString()); }
    else { this.store.version = version; }
  }
}
