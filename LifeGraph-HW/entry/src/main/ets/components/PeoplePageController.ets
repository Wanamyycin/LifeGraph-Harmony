export class PeoplePageController {
  private handler: (() => boolean) | null = null;

  bind(handler: () => boolean): void {
    this.handler = handler;
  }

  clear(): void {
    this.handler = null;
  }

  onBackPress(): boolean {
    return this.handler !== null ? this.handler() : false;
  }
}
