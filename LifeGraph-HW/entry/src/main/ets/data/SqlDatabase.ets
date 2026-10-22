import { SqlValue } from '../domain/SqlValue';
export { SqlValue } from '../domain/SqlValue';

export class SqlRow {
  values: Map<string, SqlValue> = new Map<string, SqlValue>();

  text(key: string): string {
    const value = this.values.get(key);
    return typeof value === 'string' ? value : '';
  }

  number(key: string): number {
    const value = this.values.get(key);
    return typeof value === 'number' ? value : 0;
  }

  nullableText(key: string): string | null {
    return this.values.get(key) === null ? null : this.text(key);
  }

  nullableNumber(key: string): number | null {
    return this.values.get(key) === null ? null : this.number(key);
  }
}

export interface SqlConnection {
  query(sql: string, values?: SqlValue[]): Promise<SqlRow[]>;
  execute(sql: string, values?: SqlValue[]): Promise<void>;
  begin(): Promise<void>;
  commit(): Promise<void>;
  rollback(): Promise<void>;
  close(): Promise<void>;
  getVersion(): number;
  setVersion(version: number): void;
}

// Every read and write shares this queue. A transaction never leaks work onto
// another connection, and a rejected operation does not poison later jobs.
export class SqlDatabase {
  private tail: Promise<void> = Promise.resolve();
  private connection: SqlConnection;

  constructor(connection: SqlConnection) {
    this.connection = connection;
  }

  read<T>(job: (connection: SqlConnection) => Promise<T>): Promise<T> {
    const result = this.tail.then(() => job(this.connection));
    this.tail = result.then(() => {}, () => {});
    return result;
  }

  transaction<T>(job: (connection: SqlConnection) => Promise<T>): Promise<T> {
    return this.read(async (connection: SqlConnection): Promise<T> => {
      await connection.begin();
      try {
        const value = await job(connection);
        await connection.commit();
        return value;
      } catch (error) {
        try { await connection.rollback(); } catch (rollbackError) {
          throw new Error('事务失败且回滚异常，请重新打开应用：' + String(rollbackError));
        }
        throw new Error(String(error));
      }
    });
  }

  async close(): Promise<void> {
    await this.read(async (connection: SqlConnection): Promise<void> => { await connection.close(); });
  }
}
