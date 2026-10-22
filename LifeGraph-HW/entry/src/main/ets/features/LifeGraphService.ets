import { Person } from '../domain/Person';
import { AppSnapshot, EventCard, EventDraft, EventRecord, MediaAsset, NamedItem,
  PersonDraft, ProfileConfig, RelationEdge, RelationInput } from '../domain/Models';
import { SqlConnection, SqlDatabase, SqlRow, SqlValue } from '../data/SqlDatabase';
import { ACCOUNT_SCHEMA } from '../data/Schema';
import { BACKUP_TABLES, BackupEnvelope, BackupTable } from '../domain/Backup';

export class LifeGraphService {
  private db: SqlDatabase;
  private makeId: () => string;
  private now: () => number;

  constructor(db: SqlDatabase, makeId: () => string, now: () => number) {
    this.db = db; this.makeId = makeId; this.now = now;
  }

  async initialize(): Promise<void> {
    await this.db.read(async (c: SqlConnection): Promise<void> => {
      await c.execute('PRAGMA foreign_keys = ON');
      if (c.getVersion() > 1) { throw new Error('本地数据由较新版本创建，请更新应用后打开'); }
    });
    await this.db.transaction(async (c: SqlConnection): Promise<void> => {
      if (c.getVersion() === 0) {
        for (const statement of ACCOUNT_SCHEMA.split(';')) {
          if (statement.trim().length > 0) { await c.execute(statement.trim()); }
        }
        await c.execute('CREATE TABLE app_config (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)');
        const config = new ProfileConfig();
        config.defaultPersonId = this.makeId();
        const timestamp = this.now();
        await c.execute('INSERT INTO persons(id,name,created_at,updated_at) VALUES(?,?,?,?)',
          [config.defaultPersonId, config.displayName, timestamp, timestamp]);
        await c.execute('INSERT INTO app_config(key,value) VALUES(?,?)', ['profile', JSON.stringify(config)]);
        await this.seed(c, 'relations', ['朋友', '家人', '同事', '同学']);
        await this.seed(c, 'branches', ['日常', '工作', '聚餐', '旅游', '运动']);
        await this.seed(c, 'emotions', ['开心', '平静', '激动', '愤怒', '难过', '疲惫']);
        c.setVersion(1);
      }
      const config = await this.profile(c);
      if ((await c.query('SELECT id FROM persons WHERE id=? AND deleted_at IS NULL', [config.defaultPersonId])).length !== 1) {
        throw new Error('本地个人资料不完整，请从备份恢复');
      }
    });
  }

  async snapshot(): Promise<AppSnapshot> {
    return this.db.read(async (c: SqlConnection): Promise<AppSnapshot> => {
      const snapshot = new AppSnapshot();
      snapshot.profile = await this.profile(c);
      snapshot.persons = (await c.query('SELECT * FROM persons ORDER BY updated_at DESC,id')).map(personFromRow);
      snapshot.relations = await this.named(c, 'relations');
      snapshot.branches = await this.named(c, 'branches');
      snapshot.emotions = await this.named(c, 'emotions');
      snapshot.mediaAssets = (await c.query('SELECT * FROM media_assets WHERE deleted_at IS NULL')).map(mediaFromRow);
      snapshot.edges = (await c.query('SELECT * FROM person_relations WHERE deleted_at IS NULL')).map((row: SqlRow): RelationEdge => {
        const edge = new RelationEdge(); edge.id = row.text('id');
        edge.personAId = row.text('person_a_id'); edge.personBId = row.text('person_b_id');
        edge.relationId = row.text('relation_id'); edge.strength = row.nullableNumber('relation_strength'); return edge;
      });
      const participants = await c.query('SELECT event_id,person_id FROM event_persons WHERE deleted_at IS NULL');
      const branches = await c.query('SELECT event_id,branch_id FROM event_branches WHERE deleted_at IS NULL');
      const emotions = await c.query('SELECT event_id,emotion_id FROM event_emotions WHERE deleted_at IS NULL');
      const assets = await c.query(`SELECT ea.event_id,ea.role,ea.sort_order,ma.* FROM event_assets ea
        JOIN media_assets ma ON ma.id=ea.asset_id WHERE ma.deleted_at IS NULL ORDER BY ea.sort_order`);
      const personGroups = groupRows(participants);
      const branchGroups = groupRows(branches);
      const emotionGroups = groupRows(emotions);
      const assetGroups = groupRows(assets);
      snapshot.events = (await c.query('SELECT * FROM events WHERE deleted_at IS NULL ORDER BY occurred_at DESC,created_at DESC'))
        .map((row: SqlRow): EventCard => {
          const card = new EventCard(); card.event = eventFromRow(row);
          card.personIds = (personGroups.get(card.event.id) ?? []).map((p: SqlRow) => p.text('person_id'));
          card.branchIds = (branchGroups.get(card.event.id) ?? []).map((p: SqlRow) => p.text('branch_id'));
          card.emotionIds = (emotionGroups.get(card.event.id) ?? []).map((p: SqlRow) => p.text('emotion_id'));
          card.assets = (assetGroups.get(card.event.id) ?? []).map(mediaFromRow);
          return card;
        });
      return snapshot;
    });
  }

  async savePerson(draft: PersonDraft): Promise<string> {
    if (draft.name.trim().length === 0) { throw new Error('请填写人物姓名'); }
    return this.db.transaction(async (c: SqlConnection): Promise<string> => {
      const config = await this.profile(c);
      if (draft.id === config.defaultPersonId) { throw new Error('请在个人资料中修改“我”的信息'); }
      const id = draft.id.length > 0 ? draft.id : this.makeId();
      const timestamp = this.now();
      await this.requireAvatar(c, draft.avatarAssetId);
      const previous = await c.query('SELECT avatar_asset_id FROM persons WHERE id=?', [id]);
      const previousAvatar = previous.length > 0 ? previous[0].nullableText('avatar_asset_id') : null;
      const historicalEdges = await c.query('SELECT person_a_id,person_b_id,relation_id FROM person_relations WHERE (person_a_id=? OR person_b_id=?) AND deleted_at IS NULL', [id, id]);
      if (draft.id.length > 0) {
        await this.requirePerson(c, id);
        await c.execute('UPDATE persons SET name=?,description=?,avatar_asset_id=?,updated_at=? WHERE id=?',
          [draft.name.trim(), nullable(draft.description), draft.avatarAssetId, timestamp, id]);
      } else {
        await c.execute(`INSERT INTO persons(id,name,description,avatar_asset_id,created_at,updated_at)
          VALUES(?,?,?,?,?,?)`, [id, draft.name.trim(), nullable(draft.description), draft.avatarAssetId, timestamp, timestamp]);
      }
      await c.execute('DELETE FROM person_relations WHERE person_a_id=? OR person_b_id=?', [id, id]);
      const seen = new Set<string>();
      for (const input of draft.relations) {
        const key = input.targetPersonId + ':' + input.relationId;
        if (seen.has(key)) { continue; }
        seen.add(key);
        const historical = historicalEdges.some((edge: SqlRow) => edge.text('relation_id') === input.relationId &&
          (edge.text('person_a_id') === input.targetPersonId || edge.text('person_b_id') === input.targetPersonId));
        await this.writeEdge(c, id, input, historical);
      }
      if (previousAvatar !== draft.avatarAssetId) { await this.retireAvatar(c, previousAvatar); }
      const saved = await c.query('SELECT * FROM persons WHERE id=?', [id]);
      if (saved.length !== 1 || saved[0].text('name') !== draft.name.trim()) {
        throw new Error('无法确认保存结果，请重新打开应用核对');
      }
      return id;
    });
  }

  async saveEdge(sourceId: string, input: RelationInput): Promise<void> {
    await this.db.transaction(async (c: SqlConnection): Promise<void> => { await this.writeEdge(c, sourceId, input); });
  }

  async deleteEdge(id: string): Promise<void> {
    await this.db.transaction(async (c: SqlConnection): Promise<void> => {
      await c.execute('DELETE FROM person_relations WHERE id=?', [id]);
    });
  }

  async deletePerson(id: string, strategy: string): Promise<void> {
    if (strategy !== 'clean' && strategy !== 'ghost') { throw new Error('请选择人物删除方式'); }
    await this.db.transaction(async (c: SqlConnection): Promise<void> => {
      const config = await this.profile(c);
      if (id === config.defaultPersonId) { throw new Error('不能删除“我”'); }
      await this.requirePerson(c, id);
      if (strategy === 'ghost') {
        await c.execute('UPDATE persons SET deleted_at=?,updated_at=? WHERE id=?', [this.now(), this.now(), id]);
        return;
      }
      const events = await c.query(`SELECT ep.event_id,COUNT(allp.id) AS participants FROM event_persons ep
        JOIN event_persons allp ON allp.event_id=ep.event_id AND allp.deleted_at IS NULL
        WHERE ep.person_id=? AND ep.deleted_at IS NULL GROUP BY ep.event_id`, [id]);
      for (const event of events) {
        if (event.number('participants') <= 1) { await this.deleteEventIn(c, event.text('event_id')); }
      }
      await c.execute('DELETE FROM person_relations WHERE person_a_id=? OR person_b_id=?', [id, id]);
      await c.execute('DELETE FROM event_persons WHERE person_id=?', [id]);
      await c.execute('DELETE FROM persons WHERE id=?', [id]);
      await this.markUnusedMedia(c);
    });
  }

  async saveEvent(draft: EventDraft): Promise<string> {
    if (draft.title.trim().length === 0) { throw new Error('请填写事件标题'); }
    if (draft.personIds.length === 0) { throw new Error('请至少选择一位参与者'); }
    if (!Number.isFinite(draft.occurredAt)) { throw new Error('请选择有效日期'); }
    return this.db.transaction(async (c: SqlConnection): Promise<string> => {
      const id = draft.id.length > 0 ? draft.id : this.makeId();
      const timestamp = this.now();
      if (draft.id.length > 0) {
        if ((await c.query('SELECT id FROM events WHERE id=? AND deleted_at IS NULL', [id])).length !== 1) {
          throw new Error('这条事件已不存在');
        }
        await c.execute('UPDATE events SET title=?,content=?,occurred_at=?,location_text=?,color=?,updated_at=? WHERE id=?',
          [draft.title.trim(), nullable(draft.content), draft.occurredAt, nullable(draft.locationText), draft.color, timestamp, id]);
      } else {
        await c.execute(`INSERT INTO events(id,title,content,occurred_at,location_text,visibility,color,created_at,updated_at)
          VALUES(?,?,?,?,?,?,?,?,?)`, [id, draft.title.trim(), nullable(draft.content), draft.occurredAt,
          nullable(draft.locationText), 'private', draft.color, timestamp, timestamp]);
      }
      for (const personId of Array.from(new Set<string>(draft.personIds))) {
        const active = await c.query('SELECT id FROM persons WHERE id=? AND deleted_at IS NULL', [personId]);
        if (active.length === 0) {
          const historical = draft.id.length > 0 ? await c.query(`SELECT p.id FROM persons p JOIN event_persons ep ON ep.person_id=p.id
            WHERE p.id=? AND ep.event_id=? AND ep.deleted_at IS NULL`, [personId, id]) : [];
          if (historical.length === 0) { throw new Error('所选人物已不存在'); }
        }
      }
      await c.execute('DELETE FROM event_persons WHERE event_id=?', [id]);
      for (const personId of Array.from(new Set<string>(draft.personIds))) {
        await c.execute('INSERT INTO event_persons(id,event_id,person_id,created_at,updated_at) VALUES(?,?,?,?,?)',
          [this.makeId(), id, personId, timestamp, timestamp]);
      }
      await this.replaceLabels(c, id, 'branches', 'event_branches', 'branch_id', draft.branchIds);
      await this.replaceLabels(c, id, 'emotions', 'event_emotions', 'emotion_id', draft.emotionIds);
      await c.execute('DELETE FROM event_assets WHERE event_id=?', [id]);
      let index = 0;
      for (const asset of draft.assets) {
        if ((await c.query('SELECT id FROM media_assets WHERE id=? AND deleted_at IS NULL', [asset.id])).length !== 1) {
          throw new Error('附件已不可用，请重新选择');
        }
        await c.execute('INSERT INTO event_assets(event_id,asset_id,role,sort_order,created_at) VALUES(?,?,?,?,?)',
          [id, asset.id, asset.role, index++, timestamp]);
      }
      const saved = await c.query('SELECT title FROM events WHERE id=?', [id]);
      if (saved.length !== 1 || saved[0].text('title') !== draft.title.trim()) { throw new Error('无法确认事件已保存'); }
      await this.cleanupGhosts(c);
      await this.markUnusedMedia(c);
      return id;
    });
  }

  async deleteEvent(id: string): Promise<void> {
    await this.db.transaction(async (c: SqlConnection): Promise<void> => {
      await this.deleteEventIn(c, id); await this.markUnusedMedia(c);
    });
  }

  async saveNamed(kind: string, id: string, rawName: string): Promise<void> {
    const table = namedTable(kind);
    const name = rawName.trim();
    if (name.length === 0) { throw new Error('名称不能为空'); }
    await this.db.transaction(async (c: SqlConnection): Promise<void> => {
      const duplicate = await c.query('SELECT id FROM ' + table + ' WHERE name=? AND deleted_at IS NULL AND id<>?', [name, id]);
      if (duplicate.length > 0) { throw new Error('这个名称已经存在'); }
      if (id.length > 0) {
        if ((await c.query('SELECT id FROM ' + table + ' WHERE id=? AND deleted_at IS NULL', [id])).length !== 1) {
          throw new Error('这个分类已不存在');
        }
        await c.execute('UPDATE ' + table + ' SET name=?,updated_at=? WHERE id=?', [name, this.now(), id]);
      } else {
        await c.execute('INSERT INTO ' + table + '(id,name,created_at,updated_at) VALUES(?,?,?,?)', [this.makeId(), name, this.now(), this.now()]);
      }
    });
  }

  async deleteNamed(kind: string, id: string): Promise<void> {
    const table = namedTable(kind);
    await this.db.transaction(async (c: SqlConnection): Promise<void> => {
      if (table === 'relations') { await c.execute('DELETE FROM person_relations WHERE relation_id=?', [id]); }
      if (table === 'branches') { await c.execute('DELETE FROM event_branches WHERE branch_id=?', [id]); }
      if (table === 'emotions') { await c.execute('DELETE FROM event_emotions WHERE emotion_id=?', [id]); }
      await c.execute('UPDATE ' + table + ' SET deleted_at=?,updated_at=? WHERE id=?', [this.now(), this.now(), id]);
    });
  }

  async saveProfile(config: ProfileConfig, bio: string, avatarId: string | null): Promise<void> {
    if (config.displayName.trim().length === 0) { throw new Error('请填写你的称呼'); }
    if (config.apiBaseUrl.length > 0 && !/^https?:\/\/[^\s]+$/.test(config.apiBaseUrl)) { throw new Error('服务地址需要以 http:// 或 https:// 开头'); }
    validateProfile(config);
    await this.db.transaction(async (c: SqlConnection): Promise<void> => {
      const previous = await this.profile(c);
      await this.requireAvatar(c, avatarId);
      const previousPerson = (await c.query('SELECT avatar_asset_id,description FROM persons WHERE id=?', [previous.defaultPersonId]))[0];
      const previousAvatar = previousPerson.nullableText('avatar_asset_id');
      // Keep existing records readable; apply original field limits to edits.
      if (config.displayName.trim() !== previous.displayName.trim() && config.displayName.trim().length > 24) { throw new Error('你的称呼最多 24 个字符'); }
      if (nullable(bio) !== previousPerson.nullableText('description') && bio.trim().length > 200) { throw new Error('个人见解最多 200 个字符'); }
      if (config.birthday !== previous.birthday && config.birthday.length > 0) { validateBirthday(config.birthday); }
      config.defaultPersonId = previous.defaultPersonId;
      config.displayName = config.displayName.trim();
      await c.execute('UPDATE persons SET name=?,description=?,avatar_asset_id=?,updated_at=? WHERE id=?',
        [config.displayName, nullable(bio), avatarId, this.now(), previous.defaultPersonId]);
      await c.execute('UPDATE app_config SET value=? WHERE key=?', [JSON.stringify(config), 'profile']);
      if (previousAvatar !== avatarId) { await this.retireAvatar(c, previousAvatar); }
    });
  }

  async registerMedia(asset: MediaAsset): Promise<void> {
    await this.db.transaction(async (c: SqlConnection): Promise<void> => {
      await c.execute('INSERT INTO media_assets(id,storage_path,mime_type,media_kind,created_at) VALUES(?,?,?,?,?)',
        [asset.id, asset.storagePath, asset.mimeType, asset.mediaKind, this.now()]);
    });
  }

  async avatarAsset(id: string | null): Promise<MediaAsset | null> {
    if (id === null) { return null; }
    return this.db.read(async (c: SqlConnection): Promise<MediaAsset | null> => {
      const rows = await c.query('SELECT * FROM media_assets WHERE id=? AND deleted_at IS NULL', [id]);
      return rows.length > 0 ? mediaFromRow(rows[0]) : null;
    });
  }

  async discardUnreferencedMedia(ids: string[]): Promise<MediaAsset[]> {
    return this.db.transaction(async (c: SqlConnection): Promise<MediaAsset[]> => {
      const candidates = await c.query(`SELECT * FROM media_assets ma
        WHERE NOT EXISTS(SELECT 1 FROM event_assets ea WHERE ea.asset_id=ma.id)
        AND NOT EXISTS(SELECT 1 FROM persons p WHERE p.avatar_asset_id=ma.id)`);
      const assets = candidates.filter((row: SqlRow) => ids.includes(row.text('id'))).map(mediaFromRow);
      for (const asset of assets) { await c.execute('DELETE FROM media_assets WHERE id=?', [asset.id]); }
      return assets;
    });
  }

  async unusedMedia(includeActive: boolean): Promise<MediaAsset[]> {
    return this.db.read(async (c: SqlConnection): Promise<MediaAsset[]> => {
      return (await c.query(`SELECT * FROM media_assets ma WHERE
        NOT EXISTS(SELECT 1 FROM event_assets ea WHERE ea.asset_id=ma.id)
        AND NOT EXISTS(SELECT 1 FROM persons p WHERE p.avatar_asset_id=ma.id)` +
        (includeActive ? '' : ' AND ma.deleted_at IS NOT NULL'))).map(mediaFromRow);
    });
  }

  async exportBackup(): Promise<BackupEnvelope> {
    return this.db.read(async (c: SqlConnection): Promise<BackupEnvelope> => {
      const envelope = new BackupEnvelope(); envelope.createdAt = this.now();
      for (const name of BACKUP_TABLES) {
        const table = new BackupTable(); table.name = name;
        table.columns = (await c.query('PRAGMA table_info(' + name + ')')).map((row: SqlRow) => row.text('name'));
        table.rows = (await c.query('SELECT * FROM ' + name)).map((row: SqlRow): SqlValue[] =>
          table.columns.map((column: string): SqlValue => row.values.get(column) ?? null));
        envelope.tables.push(table);
      }
      return envelope;
    });
  }

  async restoreBackup(envelope: BackupEnvelope): Promise<void> {
    if (envelope.format !== 'lifegraph-harmony' || envelope.schemaVersion !== 1 || !Array.isArray(envelope.tables) || envelope.tables.length !== BACKUP_TABLES.length) {
      throw new Error('不是受支持的鸿蒙版备份');
    }
    await this.db.transaction(async (c: SqlConnection): Promise<void> => {
      const seen = new Set<string>();
      for (const table of envelope.tables) {
        if (!BACKUP_TABLES.includes(table.name) || seen.has(table.name) || !Array.isArray(table.columns) || !Array.isArray(table.rows) || table.rows.length > 100000) {
          throw new Error('备份表结构不正确或数据规模超出当前支持范围');
        }
        seen.add(table.name);
        const expected = (await c.query('PRAGMA table_info(' + table.name + ')')).map((row: SqlRow) => row.text('name'));
        if (table.columns.length !== expected.length || new Set<string>(table.columns).size !== expected.length || table.columns.some((column: string) => !expected.includes(column))) {
          throw new Error('备份字段与当前版本不兼容');
        }
        for (const values of table.rows) {
          if (!Array.isArray(values) || values.length !== expected.length || values.some((value: SqlValue) =>
            value !== null && typeof value !== 'string' && typeof value !== 'number') || values.some((value: SqlValue) => typeof value === 'number' && !Number.isFinite(value))) {
            throw new Error('备份含有无效数据');
          }
        }
      }
      for (const name of BACKUP_TABLES.slice().reverse()) { await c.execute('DELETE FROM ' + name); }
      for (const name of BACKUP_TABLES) {
        const table = envelope.tables.find((item: BackupTable) => item.name === name);
        if (table === undefined) { throw new Error('备份缺少必要的数据表'); }
        const sql = 'INSERT INTO ' + name + '(' + table.columns.join(',') + ') VALUES(' + table.columns.map(() => '?').join(',') + ')';
        for (const values of table.rows) { await c.execute(sql, values); }
      }
      const config = await this.profile(c);
      if ((await c.query('SELECT id FROM persons WHERE id=? AND deleted_at IS NULL', [config.defaultPersonId])).length !== 1) { throw new Error('备份缺少个人节点'); }
      if ((await c.query('PRAGMA foreign_key_check')).length > 0) { throw new Error('备份中的关联数据不完整'); }
      if ((await c.query(`SELECT p.id FROM persons p LEFT JOIN media_assets ma ON ma.id=p.avatar_asset_id
        AND ma.deleted_at IS NULL AND ma.media_kind='image' WHERE p.avatar_asset_id IS NOT NULL AND ma.id IS NULL`)).length > 0) {
        throw new Error('备份中的头像附件不存在或不是有效图片');
      }
    });
  }

  private async seed(c: SqlConnection, table: string, names: string[]): Promise<void> {
    for (const name of names) {
      await c.execute('INSERT INTO ' + table + '(id,name,created_at,updated_at) VALUES(?,?,?,?)', [this.makeId(), name, this.now(), this.now()]);
    }
  }

  private async profile(c: SqlConnection): Promise<ProfileConfig> {
    const rows = await c.query('SELECT value FROM app_config WHERE key=?', ['profile']);
    if (rows.length !== 1) { throw new Error('个人配置读取失败'); }
    const config = JSON.parse(rows[0].text('value')) as ProfileConfig;
    validateProfile(config);
    return config;
  }

  private async named(c: SqlConnection, table: string): Promise<NamedItem[]> {
    return (await c.query('SELECT id,name FROM ' + table + ' WHERE deleted_at IS NULL ORDER BY created_at,id'))
      .map((row: SqlRow): NamedItem => { const item = new NamedItem(); item.id = row.text('id'); item.name = row.text('name'); return item; });
  }

  private async requirePerson(c: SqlConnection, id: string): Promise<void> {
    if ((await c.query('SELECT id FROM persons WHERE id=? AND deleted_at IS NULL', [id])).length !== 1) { throw new Error('所选人物已不存在'); }
  }

  private async requireAvatar(c: SqlConnection, id: string | null): Promise<void> {
    if (id !== null && (await c.query("SELECT id FROM media_assets WHERE id=? AND deleted_at IS NULL AND media_kind='image'", [id])).length !== 1) {
      throw new Error('头像附件已不可用，请重新选择图片');
    }
  }

  private async retireAvatar(c: SqlConnection, id: string | null): Promise<void> {
    if (id === null) { return; }
    await c.execute(`UPDATE media_assets SET deleted_at=? WHERE id=? AND deleted_at IS NULL
      AND NOT EXISTS(SELECT 1 FROM event_assets ea WHERE ea.asset_id=media_assets.id)
      AND NOT EXISTS(SELECT 1 FROM persons p WHERE p.avatar_asset_id=media_assets.id)`, [this.now(), id]);
  }

  private async writeEdge(c: SqlConnection, sourceId: string, input: RelationInput, historical: boolean = false): Promise<void> {
    if (sourceId === input.targetPersonId) { throw new Error('不能把人物关联到自己'); }
    if (input.strength !== null && (!Number.isInteger(input.strength) || input.strength < 1 || input.strength > 5)) { throw new Error('关系强度应为 1～5'); }
    await this.requirePerson(c, sourceId);
    if (historical) {
      if ((await c.query('SELECT id FROM persons WHERE id=?', [input.targetPersonId])).length !== 1) { throw new Error('所选人物已不存在'); }
    } else { await this.requirePerson(c, input.targetPersonId); }
    if ((await c.query('SELECT id FROM relations WHERE id=? AND deleted_at IS NULL', [input.relationId])).length !== 1) { throw new Error('请选择有效关系类型'); }
    const first = sourceId < input.targetPersonId ? sourceId : input.targetPersonId;
    const second = sourceId < input.targetPersonId ? input.targetPersonId : sourceId;
    const existing = await c.query('SELECT id FROM person_relations WHERE person_a_id=? AND person_b_id=? AND relation_id=? AND deleted_at IS NULL',
      [first, second, input.relationId]);
    if (existing.length > 0) {
      await c.execute('UPDATE person_relations SET relation_strength=?,updated_at=? WHERE id=?', [input.strength, this.now(), existing[0].text('id')]);
    } else {
      await c.execute(`INSERT INTO person_relations(id,person_a_id,person_b_id,relation_id,relation_strength,created_at,updated_at)
        VALUES(?,?,?,?,?,?,?)`, [this.makeId(), first, second, input.relationId, input.strength, this.now(), this.now()]);
    }
  }

  private async replaceLabels(c: SqlConnection, eventId: string, source: string, junction: string, column: string, ids: string[]): Promise<void> {
    await c.execute('DELETE FROM ' + junction + ' WHERE event_id=?', [eventId]);
    for (const id of Array.from(new Set<string>(ids))) {
      if ((await c.query('SELECT id FROM ' + source + ' WHERE id=? AND deleted_at IS NULL', [id])).length !== 1) { throw new Error('所选分类已不存在，请刷新后重试'); }
      await c.execute('INSERT INTO ' + junction + '(event_id,' + column + ',created_at) VALUES(?,?,?)', [eventId, id, this.now()]);
    }
  }

  private async deleteEventIn(c: SqlConnection, id: string): Promise<void> {
    if ((await c.query('SELECT id FROM events WHERE id=?', [id])).length === 0) { throw new Error('事件已不存在'); }
    for (const table of ['event_assets', 'event_emotions', 'event_branches', 'event_persons']) {
      await c.execute('DELETE FROM ' + table + ' WHERE event_id=?', [id]);
    }
    await c.execute('DELETE FROM events WHERE id=?', [id]);
    await this.cleanupGhosts(c);
  }

  private async cleanupGhosts(c: SqlConnection): Promise<void> {
    const ghosts = await c.query(`SELECT p.id FROM persons p WHERE p.deleted_at IS NOT NULL
      AND NOT EXISTS(SELECT 1 FROM event_persons ep WHERE ep.person_id=p.id)`);
    for (const person of ghosts) {
      await c.execute('DELETE FROM person_relations WHERE person_a_id=? OR person_b_id=?', [person.text('id'), person.text('id')]);
      await c.execute('DELETE FROM persons WHERE id=?', [person.text('id')]);
    }
  }

  private async markUnusedMedia(c: SqlConnection): Promise<void> {
    await c.execute(`UPDATE media_assets SET deleted_at=? WHERE deleted_at IS NULL
      AND NOT EXISTS(SELECT 1 FROM event_assets ea WHERE ea.asset_id=media_assets.id)
      AND NOT EXISTS(SELECT 1 FROM persons p WHERE p.avatar_asset_id=media_assets.id)`, [this.now()]);
  }
}

function groupRows(rows: SqlRow[]): Map<string, SqlRow[]> {
  const groups = new Map<string, SqlRow[]>();
  for (const row of rows) {
    const id = row.text('event_id'); const group = groups.get(id);
    if (group === undefined) { groups.set(id, [row]); } else { group.push(row); }
  }
  return groups;
}

function namedTable(kind: string): string {
  if (kind !== 'relations' && kind !== 'branches' && kind !== 'emotions') { throw new Error('未知分类'); }
  return kind;
}

function nullable(text: string): string | null { return text.trim().length > 0 ? text.trim() : null; }

function validateBirthday(value: string): void {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) { throw new Error('生日应为有效的年-月-日'); }
  const year = Number(value.slice(0, 4)); const month = Number(value.slice(5, 7)); const day = Number(value.slice(8, 10));
  const date = new Date(year, month - 1, day);
  if (year < 1900 || date.getTime() > Date.now() || date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    throw new Error('生日应为 1900 年至今天之间的有效日期');
  }
}

function validateProfile(config: ProfileConfig): void {
  if (typeof config.defaultPersonId !== 'string' || config.defaultPersonId.length === 0 || typeof config.displayName !== 'string' || config.displayName.trim().length === 0 ||
    typeof config.birthday !== 'string' || typeof config.apiBaseUrl !== 'string' || !Array.isArray(config.customEventColors) ||
    config.customEventColors.some((color: string) => typeof color !== 'string' || !/^#[a-fA-F0-9]{6}$/.test(color))) { throw new Error('个人配置格式不正确'); }
  if (!['forest', 'ocean', 'sunset', 'minimal'].includes(config.themeKey) || !['system', 'light', 'dark'].includes(config.appearance)) { throw new Error('外观配置格式不正确'); }
}

function personFromRow(row: SqlRow): Person {
  const person = new Person(); person.id = row.text('id'); person.name = row.text('name');
  person.description = row.nullableText('description'); person.avatarAssetId = row.nullableText('avatar_asset_id');
  person.createdAt = row.number('created_at'); person.updatedAt = row.number('updated_at');
  person.deletedAt = row.nullableNumber('deleted_at'); return person;
}

function eventFromRow(row: SqlRow): EventRecord {
  const event = new EventRecord(); event.id = row.text('id'); event.title = row.text('title'); event.content = row.text('content');
  event.occurredAt = row.number('occurred_at'); event.locationText = row.text('location_text');
  event.color = row.text('color') || '#5B8C5A'; event.createdAt = row.number('created_at'); event.updatedAt = row.number('updated_at'); return event;
}

function mediaFromRow(row: SqlRow): MediaAsset {
  const asset = new MediaAsset(); asset.id = row.text('id'); asset.storagePath = row.text('storage_path');
  asset.mimeType = row.text('mime_type'); asset.mediaKind = row.text('media_kind');
  asset.role = row.text('role') || 'attachment'; asset.sortOrder = row.number('sort_order'); return asset;
}
