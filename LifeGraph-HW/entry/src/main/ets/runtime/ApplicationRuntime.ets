// Only the application's real UIAbility starts this runtime. DevEco's page
// preview uses FakeUIAbility and must fail closed into visual-preview mode.
export class ApplicationRuntime {
  private static started: boolean = false;
  private static foreground: boolean = false;
  static onBackground: (() => void) | null = null;
  static onColors: ((background: string, text: string) => void) | null = null;
  static onAppearance: ((appearance: string) => void) | null = null;
  private static backgroundListeners: Map<number, () => void> = new Map<number, () => void>();
  private static nextListener: number = 0;

  static addBackgroundListener(listener: () => void): number {
    const id = ++ApplicationRuntime.nextListener;
    ApplicationRuntime.backgroundListeners.set(id, listener); return id;
  }

  static removeBackgroundListener(id: number): void { ApplicationRuntime.backgroundListeners.delete(id); }

  static enterBackground(): void {
    ApplicationRuntime.foreground = false;
    if (ApplicationRuntime.onBackground !== null) { ApplicationRuntime.onBackground(); }
    ApplicationRuntime.backgroundListeners.forEach((listener: () => void) => listener());
  }

  static start(): void {
    ApplicationRuntime.started = true;
  }

  static enterForeground(): void { ApplicationRuntime.foreground = true; }
  static isForeground(): boolean { return ApplicationRuntime.started && ApplicationRuntime.foreground; }

  static stop(): void {
    ApplicationRuntime.started = false;
    ApplicationRuntime.foreground = false;
    ApplicationRuntime.backgroundListeners.clear();
    ApplicationRuntime.onAppearance = null;
  }

  static useVisualPreview(explicitPreview: boolean): boolean {
    return explicitPreview || !ApplicationRuntime.started;
  }
}
