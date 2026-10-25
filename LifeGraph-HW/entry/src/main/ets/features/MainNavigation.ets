export enum MainTab { Graph = 0, Records = 1, People = 2, Assistant = 3 }

// A child destination covers the main tab. Legacy assistant destinations still work.
export function assistantVisible(tab: MainTab, destinations: string[]): boolean {
  return destinations.length === 0 ? tab === MainTab.Assistant : destinations[destinations.length - 1] === 'ai';
}

export function mainTitle(tab: MainTab): string {
  if (tab === MainTab.Records) { return '生活记录'; }
  if (tab === MainTab.People) { return '人物'; }
  if (tab === MainTab.Assistant) { return '助手'; }
  return 'Life Graph';
}

export function editorDestination(name: string): boolean { return name === 'personEditor' || name === 'eventEditor'; }
