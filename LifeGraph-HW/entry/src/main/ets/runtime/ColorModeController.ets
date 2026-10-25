// Deduplicate configuration callbacks; a failed platform call remains retryable.
export class ColorModeController {
  private applied: string = '';
  private apply: (mode: string) => void;
  constructor(apply: (mode: string) => void) { this.apply = apply; }

  setAppearance(appearance: string): void {
    const mode = appearance === 'dark' || appearance === 'light' ? appearance : 'system';
    if (mode === this.applied) { return; }
    this.apply(mode); this.applied = mode;
  }
}
