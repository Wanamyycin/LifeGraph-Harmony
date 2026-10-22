import { SqlValue } from './SqlValue';

export class BackupTable {
  name: string = '';
  columns: string[] = [];
  rows: SqlValue[][] = [];
}

export class BackupEnvelope {
  format: string = 'lifegraph-harmony';
  schemaVersion: number = 1;
  createdAt: number = 0;
  tables: BackupTable[] = [];
}

export const BACKUP_TABLES: string[] = ['persons', 'relations', 'branches', 'emotions', 'media_assets', 'events',
  'person_relations', 'event_persons', 'event_branches', 'event_emotions', 'event_assets', 'app_config'];
