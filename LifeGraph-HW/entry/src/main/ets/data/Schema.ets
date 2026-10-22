// Adapted from the original app schema; no user data is copied.
export const ACCOUNT_SCHEMA: string = `
CREATE TABLE IF NOT EXISTS persons (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  avatar_asset_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_persons_name ON persons(name);
CREATE INDEX IF NOT EXISTS idx_persons_deleted_at ON persons(deleted_at);

CREATE TABLE IF NOT EXISTS relations (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_relations_name_active
ON relations(name)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_relations_deleted_at ON relations(deleted_at);

CREATE TABLE IF NOT EXISTS person_relations (
  id TEXT PRIMARY KEY NOT NULL,
  person_a_id TEXT NOT NULL,
  person_b_id TEXT NOT NULL,
  relation_id TEXT NOT NULL,
  relation_strength INTEGER CHECK (
    relation_strength IS NULL OR relation_strength BETWEEN 1 AND 5
  ),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  FOREIGN KEY (person_a_id) REFERENCES persons(id),
  FOREIGN KEY (person_b_id) REFERENCES persons(id),
  FOREIGN KEY (relation_id) REFERENCES relations(id),
  CHECK (person_a_id <> person_b_id),
  CHECK (person_a_id < person_b_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_person_relations_triplet_active
ON person_relations(person_a_id, person_b_id, relation_id)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_person_relations_person_a_id ON person_relations(person_a_id);
CREATE INDEX IF NOT EXISTS idx_person_relations_person_b_id ON person_relations(person_b_id);
CREATE INDEX IF NOT EXISTS idx_person_relations_relation_id ON person_relations(relation_id);
CREATE INDEX IF NOT EXISTS idx_person_relations_deleted_at ON person_relations(deleted_at);

CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT,
  content TEXT,
  occurred_at INTEGER,
  location_text TEXT,
  visibility TEXT CHECK (
    visibility IS NULL OR visibility IN ('private', 'shared', 'public')
  ),
  color TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_events_occurred_at ON events(occurred_at);
CREATE INDEX IF NOT EXISTS idx_events_visibility ON events(visibility);
CREATE INDEX IF NOT EXISTS idx_events_title ON events(title);
CREATE INDEX IF NOT EXISTS idx_events_deleted_at ON events(deleted_at);

CREATE TABLE IF NOT EXISTS event_persons (
  id TEXT PRIMARY KEY NOT NULL,
  event_id TEXT NOT NULL,
  person_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  FOREIGN KEY (event_id) REFERENCES events(id),
  FOREIGN KEY (person_id) REFERENCES persons(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_event_persons_active
ON event_persons(event_id, person_id)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_event_persons_event_id ON event_persons(event_id);
CREATE INDEX IF NOT EXISTS idx_event_persons_person_id ON event_persons(person_id);
CREATE INDEX IF NOT EXISTS idx_event_persons_deleted_at ON event_persons(deleted_at);

CREATE TABLE IF NOT EXISTS branches (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_branches_name_active
ON branches(name)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_branches_deleted_at ON branches(deleted_at);

CREATE TABLE IF NOT EXISTS event_branches (
  event_id TEXT NOT NULL,
  branch_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  FOREIGN KEY (event_id) REFERENCES events(id),
  FOREIGN KEY (branch_id) REFERENCES branches(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_event_branches_active
ON event_branches(event_id, branch_id)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_event_branches_event_id ON event_branches(event_id);
CREATE INDEX IF NOT EXISTS idx_event_branches_branch_id ON event_branches(branch_id);
CREATE INDEX IF NOT EXISTS idx_event_branches_deleted_at ON event_branches(deleted_at);

CREATE TABLE IF NOT EXISTS emotions (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_emotions_name_active
ON emotions(name)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_emotions_deleted_at ON emotions(deleted_at);

CREATE TABLE IF NOT EXISTS event_emotions (
  event_id TEXT NOT NULL,
  emotion_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  FOREIGN KEY (event_id) REFERENCES events(id),
  FOREIGN KEY (emotion_id) REFERENCES emotions(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_event_emotions_active
ON event_emotions(event_id, emotion_id)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_event_emotions_event_id ON event_emotions(event_id);
CREATE INDEX IF NOT EXISTS idx_event_emotions_emotion_id ON event_emotions(emotion_id);
CREATE INDEX IF NOT EXISTS idx_event_emotions_deleted_at ON event_emotions(deleted_at);

CREATE TABLE IF NOT EXISTS media_assets (
  id TEXT PRIMARY KEY NOT NULL,
  storage_path TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  media_kind TEXT NOT NULL CHECK (
    media_kind IN ('image', 'video', 'audio', 'other')
  ),
  sha256 TEXT,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_media_assets_storage_path_active
ON media_assets(storage_path)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_media_assets_deleted_at ON media_assets(deleted_at);

CREATE TABLE IF NOT EXISTS event_assets (
  event_id TEXT NOT NULL,
  asset_id TEXT NOT NULL,
  role TEXT CHECK (
    role IS NULL OR role IN ('cover', 'attachment', 'voice-note')
  ),
  sort_order INTEGER CHECK (
    sort_order IS NULL OR sort_order >= 0
  ),
  created_at INTEGER NOT NULL,
  FOREIGN KEY (event_id) REFERENCES events(id),
  FOREIGN KEY (asset_id) REFERENCES media_assets(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_event_assets_unique
ON event_assets(event_id, asset_id);

CREATE INDEX IF NOT EXISTS idx_event_assets_event_id ON event_assets(event_id);
CREATE INDEX IF NOT EXISTS idx_event_assets_asset_id ON event_assets(asset_id);
CREATE INDEX IF NOT EXISTS idx_event_assets_sort_order ON event_assets(event_id, sort_order);
`;

