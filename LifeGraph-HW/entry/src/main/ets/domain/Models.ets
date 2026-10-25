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
  paper: string = '#FCFDFB';
  card: string = '#F2F5F0';
  text: string = '#243B32';
  muted: string = '#69776F';
  primary: string = '#39634E';
  onPrimary: string = '#FFFFFF';
  soft: string = '#E8EFE7';
  border: string = '#E1E7DF';
  danger: string = '#A66355';
  onDanger: string = '#FFFFFF';
}

export function darkAppearance(profile: ProfileConfig, systemDark: boolean): boolean {
  return profile.appearance === 'dark' || (profile.appearance === 'system' && systemDark);
}

export function paletteFor(profile: ProfileConfig, systemDark: boolean): Palette {
  const dark = darkAppearance(profile, systemDark);
  const p = new Palette();
  if (profile.themeKey === 'ocean') { p.primary = dark ? '#7AAED8' : '#3C7BB9'; }
  if (profile.themeKey === 'sunset') { p.primary = dark ? '#EBAA98' : '#E07A5F'; }
  if (profile.themeKey === 'sunset') { p.onPrimary = '#15261C'; }
  if (profile.themeKey === 'minimal') { p.primary = dark ? '#CCCCCC' : '#2A2A2A'; }
  if (dark) {
    p.paper = '#222D27'; p.card = '#2D3930'; p.text = '#E6ECE2';
    p.muted = '#A4B1A5'; p.soft = '#344839'; p.border = '#3A473D'; p.danger = '#E6A08D';
    if (profile.themeKey === 'forest') { p.primary = '#A6C3A1'; }
    p.onPrimary = '#15261C';
    p.onDanger = '#15261C';
  }
  return p;
}

export function graphThemeFor(profile: ProfileConfig, systemDark: boolean): string {
  return profile.themeKey + (darkAppearance(profile, systemDark) ? '-dark' : '-light');
}
