import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { Person, PersonRepository } from '../domain/Person';

export class PersonRdbRepository implements PersonRepository {
  private store: relationalStore.RdbStore | null = null;

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: 'lifegraph-native-spike.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    try {
      await store.executeSql(`CREATE TABLE IF NOT EXISTS persons (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        avatar_asset_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )`);
      store.version = 1;
      this.store = store;
    } catch (error) {
      await store.close();
      throw new Error('数据库初始化失败: ' + String(error));
    }
  }

  async listActive(): Promise<Person[]> {
    const result = await this.requireStore().querySql(
      'SELECT * FROM persons WHERE deleted_at IS NULL ORDER BY updated_at DESC, id ASC');
    const people: Person[] = [];
    try {
      while (result.goToNextRow()) {
        people.push(this.readPerson(result));
      }
    } finally {
      result.close();
    }
    return people;
  }

  async findActive(id: string): Promise<Person | null> {
    const result = await this.requireStore().querySql(
      'SELECT * FROM persons WHERE id = ? AND deleted_at IS NULL', [id]);
    try {
      return result.goToFirstRow() ? this.readPerson(result) : null;
    } finally {
      result.close();
    }
  }

  async insert(person: Person): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      id: person.id, name: person.name, description: person.description,
      avatar_asset_id: person.avatarAssetId, created_at: person.createdAt,
      updated_at: person.updatedAt, deleted_at: null
    };
    await this.requireStore().insert('persons', values);
  }

  async update(person: Person): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      name: person.name, description: person.description, updated_at: person.updatedAt
    };
    const changed = await this.requireStore().update(values, this.activeId(person.id));
    if (changed !== 1) {
      throw new Error('人物已发生变化，请返回列表刷新');
    }
  }

  async archive(id: string, timestamp: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { deleted_at: timestamp, updated_at: timestamp };
    const changed = await this.requireStore().update(values, this.activeId(id));
    if (changed !== 1) {
      throw new Error('人物已发生变化，请返回列表刷新');
    }
  }

  private activeId(id: string): relationalStore.RdbPredicates {
    return new relationalStore.RdbPredicates('persons').equalTo('id', id).isNull('deleted_at');
  }

  private requireStore(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('本地数据库尚未就绪');
    }
    return this.store;
  }

  private readPerson(result: relationalStore.ResultSet): Person {
    const person = new Person();
    person.id = result.getString(result.getColumnIndex('id'));
    person.name = result.getString(result.getColumnIndex('name'));
    const descriptionIndex = result.getColumnIndex('description');
    person.description = result.isColumnNull(descriptionIndex) ? null : result.getString(descriptionIndex);
    const avatarIndex = result.getColumnIndex('avatar_asset_id');
    person.avatarAssetId = result.isColumnNull(avatarIndex) ? null : result.getString(avatarIndex);
    person.createdAt = result.getLong(result.getColumnIndex('created_at'));
    person.updatedAt = result.getLong(result.getColumnIndex('updated_at'));
    return person;
  }
}
