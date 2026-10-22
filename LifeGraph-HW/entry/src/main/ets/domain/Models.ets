import { Person } from './Person';

export class NamedItem {
  id: string = '';
  name: string = '';
}

export class RelationEdge {
  id: string = '';
  personAId: string = '';
  personBId: string = '';
  relationId: string = '';
  strength: number | null = null;
}

export class EventRecord {
  id: string = '';
  title: string = '';
  content: string = '';
  occurredAt: number = 0;
  locationText: string = '';
  color: string = '#5B8C5A';
  createdAt: number = 0;
  updatedAt: number = 0;
}

export class MediaAsset {
  id: string = '';
  storagePath: string = '';
  mimeType: string = '';
  mediaKind: string = '';
  role: string = 'attachment';
  sortOrder: number = 0;
}

export class EventCard {
  event: EventRecord = new EventRecord();
  personIds: string[] = [];
  branchIds: string[] = [];
  emotionIds: string[] = [];
  assets: MediaAsset[] = [];
}

export class ProfileConfig {
  defaultPersonId: string = '';
  displayName: string = '我';
  birthday: string = '';
  themeKey: string = 'forest';
  appearance: string = 'system';
  customEventColors: string[] = [];
  apiBaseUrl: string = '';
}

export class AppSnapshot {
  profile: ProfileConfig = new ProfileConfig();
  persons: Person[] = [];
  relations: NamedItem[] = [];
  branches: NamedItem[] = [];
  emotions: NamedItem[] = [];
  edges: RelationEdge[] = [];
  events: EventCard[] = [];
  mediaAssets: MediaAsset[] = [];
}

export class RelationInput {
  targetPersonId: string = '';
  relationId: string = '';
  strength: number | null = 3;
}

export class PersonDraft {
  id: string = '';
  name: string = '';
  description: string = '';
  avatarAssetId: string | null = null;
  relations: RelationInput[] = [];
}

export class EventDraft {
  id: string = '';
  title: string = '';
  content: string = '';
  occurredAt: number = Date.now();
  locationText: string = '';
  color: string = '#5B8C5A';
  personIds: string[] = [];
  branchIds: string[] = [];
  emotionIds: string[] = [];
  assets: MediaAsset[] = [];
}

export class Palette {
  paper: string = '#F8F1E6';
  card: string = '#FAF5EB';
  text: string = '#3D3329';
  muted: string = '#6B5E4F';
  primary: string = '#5B8C5A';
  soft: string = '#EEE5D7';
  border: string = '#D4C4A8';
  danger: string = '#A66355';
}

export function paletteFor(profile: ProfileConfig, systemDark: boolean): Palette {
  const dark = profile.appearance === 'dark' || (profile.appearance === 'system' && systemDark);
  const p = new Palette();
  if (profile.themeKey === 'ocean') { p.primary = dark ? '#7AAED8' : '#3C7BB9'; }
  if (profile.themeKey === 'sunset') { p.primary = dark ? '#EBAA98' : '#E07A5F'; }
  if (profile.themeKey === 'minimal') { p.primary = dark ? '#CCCCCC' : '#2A2A2A'; }
  if (dark) {
    p.paper = '#201E1B'; p.card = '#2B2823'; p.text = '#F2E9DC';
    p.muted = '#BDB1A0'; p.soft = '#39332C'; p.border = '#544A3D'; p.danger = '#E6A08D';
    if (profile.themeKey === 'forest') { p.primary = '#81B29A'; }
  }
  return p;
}
