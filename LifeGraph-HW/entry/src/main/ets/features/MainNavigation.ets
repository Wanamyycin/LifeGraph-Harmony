export enum MainTab { Graph = 0, Records = 1, People = 2, Profile = 3 }

export function mainTitle(tab: MainTab): string {
  if (tab === MainTab.Records) { return '生活记录'; }
  if (tab === MainTab.People) { return '人物'; }
  if (tab === MainTab.Profile) { return '我的'; }
  return 'Life Graph';
}

export function editorDestination(name: string): boolean { return name === 'personEditor' || name === 'eventEditor'; }
