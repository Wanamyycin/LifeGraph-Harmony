import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Person } from '../domain/Person';
import { PersonRdbRepository } from '../data/PersonRdbRepository';
import { PersonService } from '../features/PersonService';
import { ApplicationRuntime } from '../runtime/ApplicationRuntime';
import { PeoplePageController } from './PeoplePageController';

// Adapted from the original forest / paper theme.
const PAPER = '#F8F1E6';
const CARD = '#FAF5EB';
const INK = '#3D3329';
const MUTED = '#6B5E4F';
const GREEN = '#5B8C5A';
const BORDER = '#E8DFCC';

@Component
export struct PeoplePage {
  controller: PeoplePageController = new PeoplePageController();
  @Prop previewOnly: boolean = false;
  @Prop previewEditor: boolean = false;
  @Prop previewPeople: Person[] = [];
  @State people: Person[] = [];
  @State keyword: string = '';
  @State ready: boolean = false;
  @State busy: boolean = false;
  @State editing: boolean = false;
  @State editingId: string = '';
  @State personName: string = '';
  @State description: string = '';
  @State errorMessage: string = '';
  @State notice: string = '';
  @State visualPreview: boolean = false;
  private repository: PersonRdbRepository = new PersonRdbRepository();
  private service: PersonService = new PersonService(this.repository,
    () => util.generateRandomUUID(), () => Date.now());

  aboutToAppear(): void {
    this.controller.bind(() => this.handleBackPress());
    this.visualPreview = ApplicationRuntime.useVisualPreview(this.previewOnly);
    if (this.visualPreview) {
      this.people = this.previewPeople;
      this.ready = true;
      this.editing = this.previewEditor;
      return;
    }
    this.initialize();
  }

  aboutToDisappear(): void {
    this.controller.clear();
  }

  private handleBackPress(): boolean {
    if (this.busy) {
      return true;
    }
    if (this.editing) {
      this.cancelEditor();
      return true;
    }
    return false;
  }

  private async initialize(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.repository.initialize(context);
      this.people = await this.service.list();
      this.ready = true;
    } catch (error) {
      hilog.error(0x0000, 'LifeGraph', 'Database initialization failed: %{public}s', String(error));
      this.errorMessage = '无法打开本地数据，请点击重试';
    } finally {
      this.busy = false;
    }
  }

  private openEditor(person: Person | null): void {
    this.editingId = person === null ? '' : person.id;
    this.personName = person === null ? '' : person.name;
    this.description = person === null ? '' : (person.description ?? '');
    this.errorMessage = '';
    this.notice = '';
    this.editing = true;
  }

  private cancelEditor(): void {
    this.editing = false;
    this.errorMessage = '';
  }

  private async savePerson(): Promise<void> {
    if (this.visualPreview) {
      this.errorMessage = '预览模式不保存，请在模拟器或真机中验证';
      return;
    }
    if (this.busy || !this.ready) {
      return;
    }
    this.busy = true;
    this.errorMessage = '';
    let expected: Person;
    try {
      expected = await this.service.save(this.editingId, this.personName, this.description);
    } catch (error) {
      hilog.error(0x0000, 'LifeGraph', 'Save failed: %{public}s', String(error));
      this.errorMessage = this.personName.trim().length === 0 ? '请填写人物姓名' : '保存失败，内容已保留，请重试';
      this.busy = false;
      return;
    }
    // Do not leave a successful insert retryable if refreshing the list fails.
    this.editing = false;
    this.keyword = '';
    await this.reloadAfterWrite('人物已保存', expected);
    this.busy = false;
  }

  private confirmArchive(): void {
    if (this.busy) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除这位人物？',
      message: '删除后，这位人物将不再出现在人物列表中。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => { this.archivePerson(); } }
    });
  }

  private async archivePerson(): Promise<void> {
    if (this.visualPreview) {
      this.errorMessage = '预览模式不删除，请在模拟器或真机中验证';
      return;
    }
    if (this.busy || !this.ready) {
      return;
    }
    this.busy = true;
    this.errorMessage = '';
    try {
      await this.service.archive(this.editingId);
    } catch (error) {
      hilog.error(0x0000, 'LifeGraph', 'Delete failed: %{public}s', String(error));
      this.errorMessage = '删除失败，请重试';
      this.busy = false;
      return;
    }
    this.editing = false;
    await this.reloadAfterWrite('人物已删除', null, this.editingId);
    this.busy = false;
  }

  private async reloadAfterWrite(message: string, expected: Person | null = null, archivedId: string = ''): Promise<void> {
    this.notice = '';
    try {
      const people = await this.service.list();
      if (expected !== null && !this.service.confirmsSave(people, expected)) {
        throw new Error('写入后未读到一致的人物记录');
      }
      if (archivedId.length > 0 && people.some((person: Person) => person.id === archivedId)) {
        throw new Error('删除后人物仍在列表中');
      }
      this.people = people;
      this.notice = message;
    } catch (error) {
      this.ready = false;
      this.errorMessage = '操作已提交，但无法确认结果，请刷新核对，勿重复提交';
      hilog.error(0x0000, 'LifeGraph', 'Reload failed: %{public}s', String(error));
    }
  }

  @Builder
  heading() {
    Row({ space: 16 }) {
      Column({ space: 6 }) {
        Text('LIFE GRAPH').fontSize(12).fontWeight(FontWeight.Bold).fontColor(GREEN).letterSpacing(2)
        Text(this.editing ? (this.editingId.length > 0 ? '编辑人物' : '记住一个人') : '我的人物')
          .fontSize(30).fontWeight(FontWeight.Bold).fontColor(INK)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (!this.editing) {
        Button('+ 新建').id('createPerson').fontSize(15).fontColor(CARD).backgroundColor(GREEN)
          .height(44).padding({ left: 18, right: 18 })
          .enabled(this.ready && !this.busy).onClick(() => this.openEditor(null))
      }
    }.width('100%')
  }

  @Builder
  feedback() {
    if (this.visualPreview) {
      Text('界面预览 · 不保存数据').id('previewNotice').fontSize(14).fontColor(GREEN)
        .width('100%').padding(12).backgroundColor('#E7EDDF').borderRadius(12)
    }
    if (this.errorMessage.length > 0) {
      Column({ space: 10 }) {
        Text(this.errorMessage).id('errorMessage').fontSize(14).fontColor('#A66355').width('100%')
        if (!this.ready) {
          Button('重试').enabled(!this.busy).onClick(() => this.initialize())
            .backgroundColor(GREEN).fontColor(Color.White)
        }
      }.width('100%').padding(14).backgroundColor('#F2E2D8').borderRadius(12)
    } else if (this.notice.length > 0) {
      Text(this.notice).id('notice').fontSize(14).fontColor(GREEN)
        .width('100%').padding(12).backgroundColor('#E7EDDF').borderRadius(12)
    }
  }

  @Builder
  personRow(person: Person) {
    Row({ space: 14 }) {
      Text(person.name.slice(0, 1)).fontSize(22).fontWeight(FontWeight.Medium).fontColor(GREEN)
        .width(48).height(48).textAlign(TextAlign.Center).backgroundColor('#E7EDDF').borderRadius(24)
      Column({ space: 6 }) {
        Text(person.name).fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(person.description ?? '还没有写下关于这个人的故事').fontSize(13).fontColor(MUTED)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(26).fontColor(MUTED)
    }.width('100%').padding(16).backgroundColor(CARD).borderRadius(18)
      .border({ width: 1, color: BORDER }).enabled(this.ready && !this.busy)
      .onClick(() => this.openEditor(person))
      .accessibilityText(person.name + '，点击编辑')
  }

  @Builder
  personList() {
    Column({ space: 16 }) {
      Text('把重要的人，留在生活的脉络里。').fontSize(14).fontColor(MUTED).width('100%')
      Search({ value: this.keyword, placeholder: '搜索姓名或人物描述' }).id('searchPeople')
        .backgroundColor(CARD).fontColor(INK).height(48).borderRadius(14)
        .onChange((value: string) => { this.keyword = value; })
      Row() {
        Text(this.keyword.trim().length > 0 ? '找到 ' + this.service.filter(this.people, this.keyword).length + ' 位人物' :
          '已记录 ' + this.people.length + ' 位人物').fontSize(13).fontColor(MUTED)
        Blank()
        Text('点击卡片编辑').fontSize(12).fontColor(MUTED)
      }.width('100%')
      if (this.busy && !this.ready) {
        LoadingProgress().width(36).height(36).color(GREEN)
        Text('正在打开本地数据…').fontSize(14).fontColor(MUTED)
      } else if (this.ready && this.service.filter(this.people, this.keyword).length === 0) {
        Column({ space: 12 }) {
          Text(this.keyword.trim().length > 0 ? '没有找到这个人' : '从一个名字开始').fontSize(22).fontColor(INK)
          Text(this.keyword.trim().length > 0 ? '换个姓名或描述关键词试试。' : '新建人物，记下你们之间的故事。')
            .fontSize(14).fontColor(MUTED).textAlign(TextAlign.Center)
          if (this.keyword.trim().length === 0) {
            Button('记下第一位人物').backgroundColor(GREEN).fontColor(CARD)
              .onClick(() => this.openEditor(null))
          }
        }.width('100%').padding({ top: 64, bottom: 40 })
      } else if (this.ready) {
        List({ space: 12 }) {
          ForEach(this.service.filter(this.people, this.keyword), (person: Person) => {
            ListItem() {
              this.personRow(person)
            }
          }, (person: Person) => person.id + ':' + person.updatedAt.toString())
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      }
      Blank().layoutWeight(this.service.filter(this.people, this.keyword).length === 0 ? 1 : 0)
      Text(this.visualPreview ? '预览数据仅用于展示' : '保存在本机 · 无需登录')
        .fontSize(12).fontColor(MUTED).padding({ bottom: 8 })
    }.width('100%').layoutWeight(1)
  }

  @Builder
  personEditor() {
    Scroll() {
      Column({ space: 18 }) {
        Text('姓名 *').fontSize(15).fontColor(INK).fontWeight(FontWeight.Medium).width('100%')
        TextInput({ text: this.personName, placeholder: '怎么称呼这个人？' }).id('personName')
          .height(52).fontSize(17).fontColor(INK).backgroundColor(CARD).borderRadius(14)
          .enabled(!this.busy).onChange((value: string) => { this.personName = value; })
        Text('关于这个人').fontSize(15).fontColor(INK).fontWeight(FontWeight.Medium).width('100%')
        TextArea({ text: this.description, placeholder: '你们如何相识？有什么想记住的事？' }).id('personDescription')
          .height(180).fontSize(16).fontColor(INK).backgroundColor(CARD).borderRadius(14)
          .enabled(!this.busy).onChange((value: string) => { this.description = value; })
        Text('姓名不能为空；描述可以留空。').fontSize(12).fontColor(MUTED).width('100%')
        Button(this.busy ? '正在保存…' : '保存人物').id('savePerson')
          .width('100%').height(52).fontSize(17).backgroundColor(GREEN).fontColor(CARD)
          .enabled(!this.busy).onClick(() => this.savePerson())
        Button('取消').id('cancelEditor').width('100%').height(48)
          .backgroundColor('#EEE5D7').fontColor(INK).enabled(!this.busy).onClick(() => this.cancelEditor())
        if (this.editingId.length > 0) {
          Button('删除人物').id('archivePerson').width('100%').height(44)
            .backgroundColor(Color.Transparent).fontColor('#A66355').enabled(!this.busy)
            .onClick(() => this.confirmArchive())
        }
      }.width('100%').padding({ bottom: 24 })
    }.width('100%').layoutWeight(1).align(Alignment.Top)
  }

  build() {
    Column({ space: 20 }) {
      this.heading()
      this.feedback()
      if (this.editing) {
        this.personEditor()
      } else {
        this.personList()
      }
    }.width('100%').height('100%').backgroundColor(PAPER)
      .padding({ top: 24, left: 24, right: 24, bottom: 12 })
  }
}
