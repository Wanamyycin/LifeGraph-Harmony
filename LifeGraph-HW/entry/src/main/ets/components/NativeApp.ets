import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { Person } from '../domain/Person';
import { AppSnapshot, EventCard, EventDraft, NamedItem, Palette, PersonDraft, ProfileConfig,
  MediaAsset, RelationEdge, RelationInput, paletteFor, graphThemeFor } from '../domain/Models';
import { LifeGraphService } from '../features/LifeGraphService';
import { AppServices } from '../application/AppServices';
import { ApplicationRuntime } from '../runtime/ApplicationRuntime';
import { PeoplePageController } from './PeoplePageController';
import { NativeGraph } from './NativeGraph';
import { buildGraph } from '../features/GraphData';
import { findEvents, formatBytes, groupTimelineEvents, timelineEvents, TimelineEventGroup, TimelineGrain } from '../features/EventQuery';
import { MediaFiles } from '../data/MediaFiles';
import { VoiceRecorder } from '../data/VoiceRecorder';
import { EventAttachments } from './EventAttachments';
import { AssistantBubble } from './AssistantBubble';
import { AssistantReference, AssistantTurn, ToolArguments, referenceUrl } from '../domain/Assistant';
import { AssistantHistory } from '../domain/AssistantHistory';
import { AssistantController, AssistantState } from '../features/AssistantController';
import { ServiceConversationStore, NativeAssistantRunner } from '../data/NativeAssistant';
import { safeMarkdownLink } from '../features/Markdown';
import { AIServicePage } from './AIServicePage';
import { AssistantEntrySheet } from './AssistantEntrySheet';
import { AssistantHistoryPage } from './AssistantHistoryPage';
import { AssistantEntryRequest } from '../features/AssistantEntry';
import { OpenAIConfig, prepareOpenAIConfig } from '../domain/OpenAIConfig';
import { AIConfigVault } from '../data/AIConfigVault';
import { RelationEditorItem } from './RelationEditorItem';
import { RelationEditorRow } from './RelationEditorRow';
import { ChoiceChip } from './ChoiceChip';
import { ActionButton } from './ActionButton';
import { PageHeading } from './PageHeading';
import { MainTabButton } from './MainTabButton';
import { FilterTab } from './FilterTab';
import { TimelineGroupSection } from './TimelineGroupSection';
import { MainTab, assistantVisible, mainTitle, editorDestination } from '../features/MainNavigation';
import { NativeBackup } from '../data/NativeBackup';
import { CardLaunch, DesktopCardConfig, cardLaunchBlocked } from '../features/DesktopCard';
import { DesktopCardStore } from '../data/DesktopCardStore';
import { DesktopCardSettings } from './DesktopCardSettings';
import { PageList, PageScroll } from './PageScroll';

class RouteParam {
  id: string = '';
  constructor(id: string = '') { this.id = id; }
}

@Component
export struct NativeApp {
  @StorageProp('nativeSystemDark') @Watch('themeChanged') systemDark: boolean = false;
  controller: PeoplePageController = new PeoplePageController();
  @Prop forcePreview: boolean = false;
  @Prop previewData: AppSnapshot = new AppSnapshot();
  @Prop previewRoute: string = '';
  @State data: AppSnapshot = new AppSnapshot();
  @State colors: Palette = new Palette();
  @State paths: NavPathStack = new NavPathStack();
  @State tab: MainTab = MainTab.Graph;
  @State ready: boolean = false;
  @State @Watch('busyChanged') busy: boolean = false;
  @State preview: boolean = false;
  @State error: string = '';
  @State notice: string = '';
  @State search: string = '';
  @State peopleSearch: string = '';
  @State eventSearch: string = '';
  @State searchKind: number = 0;
  @State personId: string = '';
  @State personName: string = '';
  @State personBio: string = '';
  @State relationInputs: RelationEditorItem[] = [];
  @State eventId: string = '';
  @State eventTitle: string = '';
  @State eventContent: string = '';
  @State eventDate: number = Date.now();
  @State eventLocation: string = '';
  @State eventColor: string = '#5B8C5A';
  @State participantIds: string[] = [];
  @State branchIds: string[] = [];
  @State emotionIds: string[] = [];
  @State filterBranchIds: string[] = [];
  @State timelineGrain: string = 'month';
  @State timelinePersonId: string = '';
  @State timelineAscending: boolean = false;
  @State timelineCollapsedGroupKeys: string[] = [];
  @State timelineExpandedEventIds: string[] = [];
  @State timelineFoldInitialized: boolean = false;
  @State tagKind: string = 'relations';
  @State tagId: string = '';
  @State tagName: string = '';
  @State profileName: string = '';
  @State profileBio: string = '';
  @State profileBirthday: string = '';
  @State graphRelationIds: string[] = [];
  @State graphBranchIds: string[] = [];
  @State homeBranchGraph: boolean = false;
  @State graphImages: Map<string, string> = new Map<string, string>();
  @State personAvatarId: string | null = null;
  @State profileAvatarId: string | null = null;
  @State eventAssets: MediaAsset[] = [];
  @State recording: boolean = false;
  @State recordingSeconds: number = 0;
  @State fullscreenUri: string = '';
  @State imageScale: number = 1;
  @State imageBaseScale: number = 1;
  @State newColor: string = '';
  @State chatLines: AssistantTurn[] = [];
  @State question: string = '';
  @State aiBusy: boolean = false;
  @State aiReady: boolean = false;
  @State aiError: string = '';
  @State aiStatus: string = '';
  @State aiConfigured: boolean = false;
  @State aiEntryOpen: boolean = false;
  @State aiEntryKind: string = 'together';
  @State aiEditing: boolean = false;
  @State aiHistory: AssistantHistory = new AssistantHistory();
  @State aiSwitching: boolean = false;
  @State aiVisibleCount: number = 40;
  @State backupMessage: string = '';
  @State storageLabel: string = '尚未统计';
  @State cardConfig: DesktopCardConfig = new DesktopCardConfig();
  private cardOpening: boolean = false;
  private assistant: AssistantController | null = null;
  private aiConversationStore: ServiceConversationStore | null = null;
  private aiDraftTimer: number = -1;
  private aiScroller: Scroller = new Scroller();
  private aiScrollTimer: number = -1;
  private chatSignature: string = '';
  private aiLinkGeneration: number = 0;
  private aiConfig: OpenAIConfig | null = null;
  private aiVault: AIConfigVault = new AIConfigVault();
  private aiScope: ToolArguments | undefined = undefined;
  private aiSettingsSaving: boolean = false;
  private aiSettingsError: string = '';
  private files: MediaFiles | null = null;
  private voice: VoiceRecorder = new VoiceRecorder();
  private recordingTimer: number = -1;
  private thumbnailGeneration: number = 0;
  private pendingMediaIds: string[] = [];
  private service: LifeGraphService | null = null;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    CardLaunch.onRequest = () => { this.handleCardLaunch(); };
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.controller.bind(() => this.goBack());
    ApplicationRuntime.onBackground = () => { if (this.recording) { this.stopRecording(); } this.pauseAssistant(); };
    this.preview = ApplicationRuntime.useVisualPreview(this.forcePreview);
    if (this.preview) {
      this.data = this.previewData; this.themeChanged(); this.ready = true; this.aiReady = true; this.resetTimelineFolds();
      if (this.previewRoute === 'personEditor') { this.editPerson(); }
      else if (this.previewRoute === 'eventEditor') { this.editEvent(); }
      else if (this.previewRoute.length > 0) { this.open(this.previewRoute); }
      return;
    }
    this.initialize();
  }

  aboutToDisappear(): void {
    this.saveAssistantDraft().catch(() => { hilog.warn(0x0000, 'LifeGraph', 'Chat draft could not be saved'); });
    this.alive = false; this.controller.clear(); this.thumbnailGeneration++;
    CardLaunch.onRequest = null;
    this.aiLinkGeneration++; this.assistant?.dispose(); clearTimeout(this.aiScrollTimer);
    ApplicationRuntime.onBackground = null; clearInterval(this.recordingTimer);
    this.voice.release().catch(() => {});
  }

  private async initialize(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.service = await AppServices.open(context);
      this.files = new MediaFiles(context); await this.files.initialize();
      await this.cleanUnusedMedia(true);
      await this.refresh();
      await this.loadAIConfig();
      await this.setupAssistant();
      if (this.alive) {
        try { await this.files.sweep(this.data.mediaAssets.map((asset: MediaAsset) => asset.storagePath)); } catch (_) {}
      }
      if (this.alive) { this.ready = true; }
    } catch (error) { if (this.alive) { this.error = readable(error); } }
    finally { if (this.alive) { this.busy = false; } }
  }

  private async refresh(): Promise<void> {
    if (this.service === null) { throw new Error('本地数据尚未就绪'); }
    const data = await this.service.snapshot();
    if (!this.alive) { return; }
    this.data = data;
    // Categories can be removed from a nested manager while an event is unsaved.
    this.branchIds = this.branchIds.filter((id: string) => data.branches.some((item: NamedItem) => item.id === id));
    this.emotionIds = this.emotionIds.filter((id: string) => data.emotions.some((item: NamedItem) => item.id === id));
    this.filterBranchIds = this.filterBranchIds.filter((id: string) => data.branches.some((item: NamedItem) => item.id === id));
    this.graphBranchIds = this.graphBranchIds.filter((id: string) => data.branches.some((item: NamedItem) => item.id === id));
    this.graphRelationIds = this.graphRelationIds.filter((id: string) => data.relations.some((item: NamedItem) => item.id === id));
    if (this.timelinePersonId.length > 0 && !data.persons.some((person: Person) => person.id === this.timelinePersonId && person.deletedAt === null)) {
      this.timelinePersonId = '';
    }
    this.relationInputs = this.relationInputs.filter((item: RelationEditorItem) => item.relationId.length === 0 || data.relations.some((relation: NamedItem) => relation.id === item.relationId));
    this.themeChanged();
    this.prepareGraphImages(data);
    if (!this.timelineFoldInitialized) { this.resetTimelineFolds(); }
    // Card publication is secondary: a launcher failure must never turn a
    // successful database write into a misleading save failure.
    if (!this.preview) {
      try { await DesktopCardStore.publish(this.getUIContext().getHostContext() as common.Context, data); }
      catch (_) { hilog.warn(0x0000, 'LifeGraphCard', 'Desktop presentation update pending'); }
    }
  }

  private async openCardSettings(): Promise<void> {
    if (!this.ready || this.busy || this.cardOpening) { return; }
    this.cardOpening = true;
    try {
      this.cardConfig = await DesktopCardStore.config(this.getUIContext().getHostContext() as common.Context);
      if (this.alive) { this.open('desktopCard'); }
    } catch (_) { if (this.alive) { this.error = '无法打开桌面卡片设置，请重试'; } }
    finally { this.cardOpening = false; }
  }

  private async handleCardLaunch(): Promise<void> {
    if (!this.alive || !this.ready || this.busy) { return; }
    const route = CardLaunch.take();
    if (route === null) { return; }
    if (cardLaunchBlocked(this.paths.getAllPathName(), this.recording, this.cardOpening || this.aiSwitching || this.aiSettingsSaving)) {
      this.notice = '请先完成当前编辑，再点击桌面卡片'; return;
    }
    if (route.action === 'settings') { await this.openCardSettings(); }
    else if (route.action === 'record') { this.editEvent(); }
    else if (this.data.persons.some((p: Person) => p.id === route.personId && p.deletedAt === null)) { this.open('person', route.personId); }
    else { this.notice = '这位人物已隐藏或删除，请重新配置桌面卡片'; }
  }

  private busyChanged(): void { if (!this.busy) { this.handleCardLaunch(); } }

  private themeChanged(): void {
    this.colors = paletteFor(this.data.profile, this.systemDark);
    if (!this.preview && ApplicationRuntime.onAppearance !== null) { ApplicationRuntime.onAppearance(this.data.profile.appearance); }
    if (ApplicationRuntime.onColors !== null) { ApplicationRuntime.onColors(this.colors.paper, this.colors.text); }
  }

  private async mutate(job: () => Promise<void>, message: string, leaveEditor: boolean = false): Promise<void> {
    if (this.preview) { this.error = '界面预览不保存数据，请在模拟器或真机运行'; return; }
    if (this.busy || !this.ready || this.service === null) { return; }
    this.busy = true; this.error = ''; this.notice = '';
    let written = false;
    try {
      await job(); written = true;
      if (!this.alive) { return; }
      if (leaveEditor && this.paths.size() > 0) { this.paths.pop(); }
      await this.refresh();
      if (leaveEditor) { await this.cleanPendingMedia(); }
      await this.cleanUnusedMedia(false);
      if (this.alive) { this.notice = message; }
    } catch (error) {
      if (this.alive) {
        this.error = written ? '操作已提交，刷新未完成，请重新打开核对，勿重复提交' : readable(error);
        if (written) { this.ready = false; }
      }
      hilog.error(0x0000, 'LifeGraph', '%{public}s', String(error));
    } finally { if (this.alive) { this.busy = false; } }
  }

  private core(): LifeGraphService {
    if (this.service === null) { throw new Error('数据服务尚未启动'); }
    return this.service;
  }

  private open(name: string, id: string = ''): void {
    if (this.busy || this.aiSwitching || !this.ready) { return; }
    if (this.recording) { this.error = '请先停止录音再离开'; return; }
    this.error = ''; this.notice = '';
    // All assistant entry points use one list/scroller and one conversation view.
    if (name === 'ai') { this.paths.clear(); this.selectTab(MainTab.Assistant); this.scrollChat(); return; }
    if (name !== 'ai' && name !== 'aiHistory' && assistantVisible(this.tab, this.paths.getAllPathName())) { this.pauseAssistant(); }
    if (name === 'people') { this.peopleSearch = ''; }
    if (name === 'events') { this.eventSearch = ''; }
    if (name === 'search') { this.search = ''; }
    this.paths.pushPathByName(name, new RouteParam(id));
  }

  private async pauseAssistant(): Promise<void> {
    this.aiLinkGeneration++; clearTimeout(this.aiScrollTimer);
    await this.assistant?.cancel();
    try { await this.saveAssistantDraft(); }
    catch (_) { if (this.alive) { this.error = '未发送的内容暂未保存，请重试'; } }
  }

  private selectTab(tab: MainTab): void {
    if (this.busy || this.aiSwitching || !this.ready || this.recording || this.paths.size() > 0 || tab === this.tab) { return; }
    if (this.tab === MainTab.Assistant) { this.pauseAssistant(); }
    this.tab = tab; this.error = ''; this.notice = '';
    if (tab === MainTab.Assistant) { this.scrollChat(); }
  }

  private goBack(): boolean {
    if (this.busy || this.aiSettingsSaving || this.aiSwitching) { return true; }
    if (this.recording) { this.error = '请先停止录音再离开'; return true; }
    const pages = this.paths.getAllPathName();
    const current = pages[pages.length - 1] ?? '';
    if (current === 'personEditor' || current === 'eventEditor' || current === 'profileEditor') {
      if (this.pendingMediaIds.length > 0) { this.cleanPendingMedia(); }
    }
    if (current === 'ai') { this.pauseAssistant(); }
    if (this.paths.size() > 0) { this.paths.pop(); this.error = ''; this.notice = ''; return true; }
    if (this.tab !== MainTab.Graph) { this.selectTab(MainTab.Graph); return true; }
    return false;
  }

  private people(global: boolean = false): Person[] {
    const query = (global ? this.search : this.peopleSearch).trim().toLocaleLowerCase();
    return this.data.persons.filter((person: Person) => person.deletedAt === null && person.id !== this.data.profile.defaultPersonId &&
      (person.name.toLocaleLowerCase().includes(query) || (person.description ?? '').toLocaleLowerCase().includes(query)));
  }

  private participants(): Person[] { return this.data.persons.filter((person: Person) => person.deletedAt === null); }
  private eventParticipants(): Person[] { return this.data.persons.filter((person: Person) => person.deletedAt === null || this.participantIds.includes(person.id)); }
  private person(id: string): Person | undefined { return this.data.persons.find((person: Person) => person.id === id); }
  private personLabel(id: string): string {
    const person = this.person(id);
    return person === undefined ? '已删除的人物' : person.name + (person.deletedAt !== null ? '（已隐藏）' : '');
  }
  private self(): Person | undefined { return this.person(this.data.profile.defaultPersonId); }
  private namedLabel(items: NamedItem[], ids: string[]): string {
    return items.filter((item: NamedItem) => ids.includes(item.id)).map((item: NamedItem) => item.name).join(' · ');
  }
  private relationSummary(id: string): string {
    const edges = this.data.edges.filter((edge) => (edge.personAId === id && edge.personBId === this.data.profile.defaultPersonId) ||
      (edge.personBId === id && edge.personAId === this.data.profile.defaultPersonId));
    return this.namedLabel(this.data.relations, edges.map((edge) => edge.relationId));
  }
  private events(global: boolean = false): EventCard[] {
    return findEvents(this.data, global ? this.search : this.eventSearch, global ? [] : this.filterBranchIds);
  }

  private timelinePeople(): Person[] {
    return this.data.persons.filter((person: Person) => person.deletedAt === null && person.id !== this.data.profile.defaultPersonId);
  }

  private timelinePersonOptions(): SelectOption[] {
    return [{ value: '全部' }, ...this.timelinePeople().map((person: Person): SelectOption => ({ value: '与' + person.name}))];
  }

  private timelinePersonIndex(): number {
    if (this.timelinePersonId.length === 0) { return 0; }
    const index = this.timelinePeople().findIndex((person: Person) => person.id === this.timelinePersonId);
    return index < 0 ? 0 : index + 1;
  }

  private timelinePersonLabel(): string {
    if (this.timelinePersonId.length === 0) { return '全部'; }
    const person = this.person(this.timelinePersonId);
    return person === undefined ? '全部' : '与' + person.name;
  }

  private timelineCards(ascending: boolean = this.timelineAscending): EventCard[] {
    return timelineEvents(this.data, { query: this.eventSearch, branchIds: this.filterBranchIds,
      personId: this.timelinePersonId, grain: this.timelineGrain as TimelineGrain, ascending: ascending });
  }

  private timelineGroups(): TimelineEventGroup[] {
    return groupTimelineEvents(this.timelineCards(), this.timelineGrain as TimelineGrain);
  }

  private setTimelinePerson(selected: number): void {
    const people = this.timelinePeople();
    this.timelinePersonId = selected <= 0 || people[selected - 1] === undefined ? '' : people[selected - 1].id;
    this.timelineExpandedEventIds = []; this.resetTimelineFolds();
  }

  private toggleTimelineOrder(): void {
    this.timelineAscending = !this.timelineAscending; this.timelineExpandedEventIds = []; this.resetTimelineFolds();
  }

  private toggleTimelineGroup(key: string): void {
    this.timelineCollapsedGroupKeys = this.timelineCollapsedGroupKeys.includes(key) ?
      this.timelineCollapsedGroupKeys.filter((item: string) => item !== key) : [...this.timelineCollapsedGroupKeys, key];
  }

  private toggleTimelineEvent(id: string): void {
    this.timelineExpandedEventIds = this.timelineExpandedEventIds.includes(id) ?
      this.timelineExpandedEventIds.filter((item: string) => item !== id) : [...this.timelineExpandedEventIds, id];
  }

  private resetTimelineFolds(): void {
    const groups = groupTimelineEvents(this.timelineCards(), this.timelineGrain as TimelineGrain);
    this.timelineCollapsedGroupKeys = groups.slice(1).map((group: TimelineEventGroup) => group.key);
    this.timelineFoldInitialized = true;
  }

  private eventRowKey(card: EventCard): string {
    return card.event.id + ':' + card.event.updatedAt + ':' + card.personIds.map((id: string) => this.personLabel(id)).join('|') +
      ':' + this.namedLabel(this.data.branches, card.branchIds) + ':' + this.namedLabel(this.data.emotions, card.emotionIds);
  }

  private editPerson(id: string = ''): void {
    if (this.busy || !this.ready || this.recording) { return; }
    const person = this.person(id);
    this.personId = id; this.personName = person?.name ?? ''; this.personBio = person?.description ?? '';
    this.personAvatarId = person?.avatarAssetId ?? null;
    this.relationInputs = this.data.edges.filter((edge) => edge.personAId === id || edge.personBId === id).map((edge): RelationEditorItem => {
      const input = new RelationInput(); input.targetPersonId = edge.personAId === id ? edge.personBId : edge.personAId;
      input.relationId = edge.relationId; input.strength = edge.strength; return new RelationEditorItem(input);
    });
    this.open('personEditor');
  }

  private async savePerson(): Promise<void> {
    const draft = new PersonDraft(); draft.id = this.personId; draft.name = this.personName; draft.description = this.personBio;
    draft.avatarAssetId = this.personAvatarId;
    draft.relations = this.relationInputs.map((item: RelationEditorItem) => item.toInput());
    await this.mutate(async (): Promise<void> => { await this.core().savePerson(draft); }, '人物已保存', true);
  }

  private editEvent(id: string = ''): void {
    if (this.busy || !this.ready || this.recording) { return; }
    const card = this.data.events.find((event: EventCard) => event.event.id === id);
    this.eventId = id; this.eventTitle = card?.event.title ?? ''; this.eventContent = card?.event.content ?? '';
    this.eventDate = card?.event.occurredAt ?? Date.now(); this.eventLocation = card?.event.locationText ?? '';
    this.eventColor = card?.event.color ?? this.colors.primary;
    this.participantIds = card?.personIds ?? (this.data.profile.defaultPersonId.length > 0 ? [this.data.profile.defaultPersonId] : []);
    this.branchIds = card?.branchIds ?? []; this.emotionIds = card?.emotionIds ?? [];
    this.eventAssets = card?.assets ?? [];
    this.open('eventEditor');
  }

  private async saveEvent(): Promise<void> {
    if (this.recording) { this.error = '请先停止录音，再保存事件'; return; }
    const draft = new EventDraft(); draft.id = this.eventId; draft.title = this.eventTitle; draft.content = this.eventContent;
    draft.occurredAt = this.eventDate; draft.locationText = this.eventLocation; draft.color = this.eventColor;
    draft.personIds = this.participantIds; draft.branchIds = this.branchIds; draft.emotionIds = this.emotionIds;
    draft.assets = this.eventAssets;
    await this.mutate(async (): Promise<void> => { await this.core().saveEvent(draft); }, '事件已保存', true);
  }

  private setEventCover(id: string): void {
    this.eventAssets = this.eventAssets.map((asset: MediaAsset): MediaAsset => {
      const copy = JSON.parse(JSON.stringify(asset)) as MediaAsset;
      if (copy.mediaKind === 'image') { copy.role = copy.id === id ? 'cover' : 'attachment'; }
      return copy;
    });
  }

  private addRelation(): void {
    const input = new RelationInput(); input.targetPersonId = this.data.profile.defaultPersonId;
    input.relationId = this.data.relations[0]?.id ?? '';
    this.relationInputs = [...this.relationInputs, new RelationEditorItem(input)];
  }

  private chooseDate(): void {
    this.getUIContext().showDatePickerDialog({ selected: new Date(this.eventDate),
      onDateAccept: (date: Date) => { this.eventDate = date.getTime(); } });
  }

  private confirmDeletePerson(id: string): void {
    this.getUIContext().showAlertDialog({ title: '删除人物', message: '保留历史：从人物列表隐藏，保留关联事件。彻底删除：移除人物及关联，仅由此人参与的事件也会删除。',
      buttons: [
        { value: '取消', action: () => {} },
        { value: '保留历史', action: () => { this.mutate(async (): Promise<void> => { await this.core().deletePerson(id, 'ghost'); }, '人物已隐藏', true); } },
        { value: '彻底删除', action: () => { this.mutate(async (): Promise<void> => { await this.core().deletePerson(id, 'clean'); }, '人物已删除', true); } }
      ] });
  }

  private confirmDeleteEvent(id: string): void {
    this.getUIContext().showAlertDialog({ title: '删除这条记录？', message: '事件、参与者关联和附件关联将一并移除。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => { this.mutate(async (): Promise<void> => { await this.core().deleteEvent(id); }, '事件已删除', true); } } });
  }

  private openTags(kind: string): void {
    if (this.busy || !this.ready || this.recording) { return; }
    this.tagKind = kind; this.tagName = ''; this.tagId = ''; this.open('tags');
  }
  private tags(): NamedItem[] { return this.tagKind === 'relations' ? this.data.relations : (this.tagKind === 'branches' ? this.data.branches : this.data.emotions); }
  private async saveTag(): Promise<void> {
    await this.mutate(async (): Promise<void> => { await this.core().saveNamed(this.tagKind, this.tagId, this.tagName); }, '分类已保存');
    if (this.error.length === 0) { this.tagName = ''; this.tagId = ''; }
  }

  private async removeTag(id: string): Promise<void> {
    await this.mutate(async (): Promise<void> => { await this.core().deleteNamed(this.tagKind, id); }, '分类已删除');
    if (this.error.length === 0 && this.tagId === id) { this.tagId = ''; this.tagName = ''; }
  }

  private editProfile(): void {
    if (this.busy || !this.ready || this.recording) { return; }
    this.profileName = this.data.profile.displayName; this.profileBio = this.self()?.description ?? '';
    this.profileBirthday = this.data.profile.birthday; this.open('profileEditor');
    this.profileAvatarId = this.self()?.avatarAssetId ?? null;
  }

  private async saveProfile(): Promise<void> {
    const config = JSON.parse(JSON.stringify(this.data.profile)) as ProfileConfig;
    config.displayName = this.profileName; config.birthday = this.profileBirthday;
    await this.mutate(async (): Promise<void> => { await this.core().saveProfile(config, this.profileBio, this.profileAvatarId); }, '个人资料已保存', true);
  }

  private async appearance(theme: string, mode: string): Promise<void> {
    const config = JSON.parse(JSON.stringify(this.data.profile)) as ProfileConfig;
    config.themeKey = theme; config.appearance = mode;
    await this.mutate(async (): Promise<void> => { await this.core().saveProfile(config, this.self()?.description ?? '', this.self()?.avatarAssetId ?? null); }, '外观已保存');
  }

  private graphPayload(mode: string, centerId: string): string {
    return JSON.stringify(buildGraph(this.data, mode, centerId, this.graphRelationIds, this.graphBranchIds, this.colors, this.graphImages));
  }

  private graphTheme(): string {
    return graphThemeFor(this.data.profile, this.systemDark);
  }

  private graphPerson(id: string): void {
    if (id === this.data.profile.defaultPersonId) { this.editProfile(); }
    else if (this.person(id) !== undefined) { this.open('person', id); }
  }

  private assetUri(id: string | null): string {
    if (this.files === null || id === null) { return ''; }
    const asset = this.data.mediaAssets.find((item: MediaAsset) => item.id === id);
    return asset !== undefined ? this.files.uri(asset) : '';
  }

  private async prepareGraphImages(data: AppSnapshot): Promise<void> {
    if (this.files === null) { return; }
    const generation = ++this.thumbnailGeneration;
    const images = new Map<string, string>();
    for (const asset of data.mediaAssets.filter((item: MediaAsset) => item.mediaKind === 'image')) {
      if (!this.alive || generation !== this.thumbnailGeneration) { return; }
      try { images.set(asset.id, await this.files.thumbnail(asset)); } catch (_) { /* Missing images keep a text node. */ }
    }
    if (this.alive && generation === this.thumbnailGeneration) { this.graphImages = images; }
  }

  private async pickMedia(kind: string, destination: string = 'event'): Promise<void> {
    if (this.preview) { this.error = '请在模拟器或真机中选择媒体'; return; }
    if (this.busy || this.files === null || this.recording) { return; }
    this.busy = true; this.error = '';
    try {
      const uris = kind === 'image' ? await this.files.chooseImages(destination === 'event' ? 9 : 1) : await this.files.chooseAudio();
      for (const uri of uris) {
        const asset = await this.files.import(uri, kind);
        try { await this.core().registerMedia(asset); } catch (error) { await this.files.remove(asset); throw new Error(String(error)); }
        this.pendingMediaIds.push(asset.id);
        if (destination === 'person') { this.personAvatarId = asset.id; }
        else if (destination === 'profile') { this.profileAvatarId = asset.id; }
        else { this.eventAssets = [...this.eventAssets, asset]; }
      }
      await this.refresh();
    } catch (error) { this.error = readable(error); }
    finally { this.busy = false; }
  }

  private async startRecording(): Promise<void> {
    if (this.preview) { this.error = '请在模拟器或真机中录音'; return; }
    if (this.busy || this.recording) { return; }
    this.busy = true; this.error = '';
    try {
      await this.voice.start(this.getUIContext().getHostContext() as common.UIAbilityContext);
      if (!this.alive || !ApplicationRuntime.isForeground()) { await this.voice.release(); return; }
      this.recording = true; this.recordingSeconds = 0;
      this.recordingTimer = setInterval(() => { this.recordingSeconds++; }, 1000);
    } catch (error) { if (this.alive) { this.error = readable(error); } }
    finally { if (this.alive) { this.busy = false; } }
  }

  private async stopRecording(): Promise<void> {
    if (!this.recording || this.files === null) { return; }
    this.recording = false; this.busy = true; clearInterval(this.recordingTimer);
    let path = '';
    try {
      path = await this.voice.stop();
      if (!this.alive) { return; }
      const asset = await this.files.import(path, 'audio');
      try { await this.core().registerMedia(asset); } catch (error) { await this.files.remove(asset); throw new Error(String(error)); }
      this.pendingMediaIds.push(asset.id);
      this.eventAssets = [...this.eventAssets, asset]; await this.refresh();
      this.notice = '语音已加入当前事件，保存事件后保留';
    } catch (error) { if (this.alive) { this.error = readable(error); } }
    finally { if (path.length > 0) { await this.voice.removeCapture(path); } if (this.alive) { this.busy = false; } }
  }

  private async cleanUnusedMedia(startup: boolean): Promise<void> {
    if (this.files === null || this.service === null) { return; }
    try {
      const unused = await this.core().unusedMedia(startup);
      for (const asset of unused) {
        await this.files.remove(asset);
        await this.core().discardUnreferencedMedia([asset.id]);
      }
    } catch (error) { hilog.warn(0x0000, 'LifeGraph', 'Media cleanup deferred: %{public}s', String(error)); }
  }

  private async cleanPendingMedia(): Promise<void> {
    if (this.service === null || this.files === null) { return; }
    const ids = this.pendingMediaIds; this.pendingMediaIds = [];
    try {
      const unused = await this.core().discardUnreferencedMedia(ids);
      for (const asset of unused) { await this.files.remove(asset); }
    } catch (error) { hilog.warn(0x0000, 'LifeGraph', 'Temporary media cleanup deferred: %{public}s', String(error)); }
  }

  private openImage(uri: string): void {
    this.fullscreenUri = uri; this.imageScale = 1; this.imageBaseScale = 1; this.open('image');
  }

  private eventColors(): string[] {
    return Array.from(new Set<string>(['#E6B8A2', '#E07A5F', '#5B8C5A', '#4A7C9D', '#D4A574', '#9D8189',
      ...this.data.profile.customEventColors]));
  }

  private async saveColors(remove: string = ''): Promise<void> {
    const color = this.newColor.trim().toUpperCase();
    if (remove.length === 0 && !/^#[0-9A-F]{6}$/.test(color)) { this.error = '请输入六位颜色值，例如 #5B8C5A'; return; }
    const config = JSON.parse(JSON.stringify(this.data.profile)) as ProfileConfig;
    config.customEventColors = remove.length > 0 ? config.customEventColors.filter((item: string) => item !== remove) :
      Array.from(new Set<string>([...config.customEventColors, color]));
    await this.mutate(async (): Promise<void> => {
      await this.core().saveProfile(config, this.self()?.description ?? '', this.self()?.avatarAssetId ?? null);
    }, '事件颜色已保存');
    if (this.error.length === 0) { this.newColor = ''; }
  }

  private async loadAIConfig(): Promise<void> {
    try {
      this.aiConfig = await this.aiVault.load(); this.aiConfigured = this.aiConfig !== null;
      this.aiSettingsError = '';
    } catch (_) {
      this.aiSettingsError = '安全配置暂时无法读取。可重新填写并保存，或取消“在本机安全保存”仅本次使用。';
    }
  }

  private openAISettings(): void {
    if (this.aiBusy || this.busy || !this.alive) { return; }
    this.open('aiSettings');
  }

  private async saveAIConfig(url: string, key: string, model: string, remember: boolean): Promise<void> {
    if (this.preview) { throw new Error('界面预览不保存配置，请运行实际应用'); }
    if (this.aiBusy || this.busy || this.aiSettingsSaving) { throw new Error('请等待当前操作结束后再保存'); }
    this.aiSettingsSaving = true;
    try {
      const config = prepareOpenAIConfig(url, key, model, this.aiConfig);
      if (remember) { await this.aiVault.save(config); }
      if (!this.alive) { return; }
      this.aiConfig = config; this.aiConfigured = true; this.aiSettingsError = ''; this.error = '';
      this.notice = remember ? 'AI 配置已安全保存' : 'AI 配置已应用，仅本次使用';
    } finally { this.aiSettingsSaving = false; }
  }

  private async askAI(): Promise<void> {
    if (this.preview) { this.error = '请在模拟器或真机中连接 AI 服务'; return; }
    if (this.aiBusy || this.aiSwitching || this.busy || this.question.trim().length === 0) { return; }
    clearTimeout(this.aiDraftTimer);
    this.getUIContext().getFocusController().clearFocus(); this.aiEditing = false;
    if (this.aiConfig === null) { this.openAISettings(); return; }
    if (!this.aiReady || this.assistant === null) { this.error = '聊天记录尚未就绪，请稍后或从历史聊天中重新选择'; return; }
    const question = this.question.trim(); const scope = this.aiScope;
    this.question = ''; this.aiScope = undefined; this.error = ''; this.notice = '';
    await this.assistant.send(question, scope);
  }

  private startAssistantEntry(request: AssistantEntryRequest): void {
    this.aiEntryOpen = false; this.question = request.question; this.aiScope = request.scope;
    this.askAI();
  }

  private async setupAssistant(): Promise<void> {
    this.aiLinkGeneration++;
    await this.assistant?.cancel();
    this.assistant?.dispose(); this.aiReady = false;
    this.aiVisibleCount = 40; this.chatSignature = '';
    const store = new ServiceConversationStore(this.core(), (history: AssistantHistory) => {
      if (!this.alive) { return; }
      this.aiHistory = history;
      const chat = history.chats.find((item) => item.id === history.activeId);
      this.question = chat === undefined ? history.draft : chat.draft;
      this.aiScope = chat === undefined ? history.draftScope : chat.draftScope;
    }, (history: AssistantHistory) => { if (this.alive && this.aiConversationStore === store) { this.aiHistory = history; } });
    this.aiConversationStore = store;
    this.assistant = new AssistantController(store,
      () => {
        if (this.aiConfig === null) { throw new Error('请先填写接口 URL、API Key 和模型名称'); }
        return new NativeAssistantRunner(this.core(), this.aiConfig);
      }, (state: AssistantState) => {
        if (!this.alive) { return; }
        this.chatLines = state.turns; this.aiBusy = state.busy; this.aiReady = state.ready; this.aiError = state.error; this.aiStatus = state.progress;
        if (state.turns.length === 0) { this.aiVisibleCount = 40; }
        const last = state.turns[state.turns.length - 1]; const signature = state.turns.length.toString() + ':' + (last?.id ?? '') + ':' + (last?.status ?? '');
        if (signature !== this.chatSignature) { this.chatSignature = signature; this.scrollChat(); }
      }, (text: string) => { if (this.alive) { this.aiStatus = text; } });
    await this.assistant.load();
  }

  private async saveAssistantDraft(): Promise<void> {
    clearTimeout(this.aiDraftTimer);
    if (this.preview || this.service === null || this.aiConversationStore === null) { return; }
    await this.core().saveAssistantDraft(this.aiConversationStore.conversationId(), this.question, this.aiScope);
  }

  private draftChanged(): void {
    clearTimeout(this.aiDraftTimer);
    this.aiDraftTimer = setTimeout(() => {
      this.saveAssistantDraft().catch(() => { if (this.alive) { this.error = '未发送的内容暂未保存，请重试'; } });
    }, 400);
  }

  private async openAssistantHistory(): Promise<void> {
    if (this.aiSwitching || this.busy) { return; }
    if (this.preview) { this.open('aiHistory'); return; }
    this.aiSwitching = true;
    this.getUIContext().getFocusController().clearFocus(); this.aiEditing = false;
    try {
      await this.assistant?.cancel(); await this.saveAssistantDraft();
      const history = await this.core().loadAssistantHistory();
      if (this.alive) { this.aiHistory = history; this.aiSwitching = false; this.open('aiHistory'); }
    } catch (error) { if (this.alive) { this.error = readable(error); } }
    finally { if (this.alive) { this.aiSwitching = false; } }
  }

  private async switchAssistantChat(id: string): Promise<void> {
    if (this.aiSwitching || this.busy || this.preview) { return; }
    this.aiSwitching = true; this.aiLinkGeneration++;
    this.getUIContext().getFocusController().clearFocus(); this.aiEditing = false;
    try {
      await this.assistant?.cancel(); await this.saveAssistantDraft();
      await this.core().activateAssistantChat(id);
      if (!this.alive) { return; }
      await this.setupAssistant();
      if (this.paths.getAllPathName().slice(-1)[0] === 'aiHistory') { this.paths.pop(); }
      this.scrollChat();
    } catch (error) { if (this.alive) { this.error = readable(error); } }
    finally { if (this.alive) { this.aiSwitching = false; } }
  }

  private scrollChat(): void {
    clearTimeout(this.aiScrollTimer);
    let answerIndex = this.chatLines.length - 1;
    while (answerIndex >= 0 && this.chatLines[answerIndex].user) { answerIndex--; }
    if (answerIndex < 0) { answerIndex = this.chatLines.length - 1; }
    if (answerIndex >= 0) { this.aiVisibleCount = Math.max(this.aiVisibleCount, this.chatLines.length - answerIndex); }
    this.aiScrollTimer = setTimeout(() => {
      if (this.alive && assistantVisible(this.tab, this.paths.getAllPathName())) {
        try {
          if (answerIndex < 0) { this.aiScroller.scrollEdge(Edge.Top); }
          else {
            const hidden = Math.max(0, this.chatLines.length - this.aiVisibleCount);
            this.aiScroller.scrollToIndex(answerIndex - hidden + (hidden > 0 ? 1 : 0), false, ScrollAlign.START);
          }
        } catch (_) {}
      }
    }, 60);
  }

  private clearConversation(): void {
    this.getUIContext().showAlertDialog({ title: '删除这段聊天？', message: '仅删除这段聊天及其消息。其他聊天、人物和经历记录会保留。',
      primaryButton: { value: '取消', fontColor: this.colors.text, action: () => {} },
      secondaryButton: { value: '删除聊天', fontColor: this.colors.danger, action: () => {
        clearTimeout(this.aiDraftTimer); this.aiLinkGeneration++; this.question = ''; this.aiScope = undefined; this.assistant?.clear();
      } } });
  }

  private async copyAnswer(text: string): Promise<void> {
    try { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)); this.notice = '已复制全文'; }
    catch (_) { this.error = '复制未完成，可长按文字复制'; }
  }

  private async assistantLink(url: string, refs: AssistantReference[]): Promise<void> {
    if (!this.alive) { return; }
    const generation = ++this.aiLinkGeneration;
    const safe = safeMarkdownLink(url);
    if (safe.length === 0) { this.error = '该链接无法打开'; return; }
    if (/^https?:\/\//i.test(safe)) {
      try { await (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({ action: 'ohos.want.action.viewData', uri: safe, entities: ['entity.system.browsable'] }); }
      catch (_) { this.error = '系统浏览器未能打开该链接'; }
      return;
    }
    const ref = refs.find((entry: AssistantReference) => referenceUrl(entry) === safe);
    if (ref === undefined) { this.error = '该引用未在查询结果中核对'; return; }
    await this.assistant?.cancel();
    if (!this.alive || generation !== this.aiLinkGeneration || !assistantVisible(this.tab, this.paths.getAllPathName())) { return; }
    if (ref.kind === 'event') {
      if (this.data.events.some((card: EventCard) => card.event.id === ref.id)) { this.open('event', ref.id); }
      else { this.error = '原事件已删除或已被恢复的备份替换'; }
    } else if (ref.kind === 'person') {
      if (this.person(ref.id) === undefined) { this.error = '原人物已删除或已被恢复的备份替换'; }
      else if (ref.id === this.data.profile.defaultPersonId) { this.editProfile(); }
      else { this.open('person', ref.id); }
    } else if (ref.id === 'ai') { this.notice = 'AI 提供查询与分析建议；人物、事件和手动强度由你修改。'; }
    else if (['people', 'events', 'search', 'appearance', 'backup'].includes(ref.id)) {
      if (ref.id === 'events') { this.filterBranchIds = []; }
      if (ref.id === 'backup') { this.updateStorage(); }
      this.open(ref.id);
    }
  }

  private backup(): NativeBackup {
    if (this.files === null) { throw new Error('本地文件服务尚未就绪'); }
    return new NativeBackup(this.getUIContext().getHostContext() as common.UIAbilityContext, this.core(), this.files);
  }

  private async exportBackup(): Promise<void> {
    if (this.preview) { this.error = '请在模拟器或真机中导出备份'; return; }
    if (this.busy) { return; }
    this.busy = true; this.error = ''; this.backupMessage = '正在准备备份，请稍候…';
    try { this.backupMessage = await this.backup().export() ? '备份已导出' : '已取消导出'; }
    catch (error) { this.error = readable(error); this.backupMessage = ''; }
    finally { this.busy = false; }
  }

  private async chooseBackup(): Promise<void> {
    if (this.preview) { this.error = '请在模拟器或真机中恢复备份'; return; }
    if (this.busy) { return; }
    this.busy = true; this.error = '';
    let uri: string | null = null;
    try {
      uri = await this.backup().choose();
      if (uri === null) { return; }
      const preview = await this.backup().preview(uri);
      const selected = uri;
      this.getUIContext().showAlertDialog({ title: '从备份恢复？',
        message: '备份时间：' + preview.date + '\n人物记录（含我）：' + preview.people + '\n事件：' + preview.events +
          '\n\n将替换当前本机记录，建议先导出一份备份。校验失败时保留当前数据。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '恢复记录', action: () => { this.restoreBackup(selected); } } });
    } catch (error) { this.error = readable(error); }
    finally { this.busy = false; }
  }

  private async restoreBackup(uri: string): Promise<void> {
    this.backupMessage = '正在校验并恢复记录…';
    await this.mutate(async (): Promise<void> => {
      await this.assistant?.cancel();
      clearTimeout(this.aiDraftTimer);
      await this.backup().restore(uri);
      this.files = new MediaFiles(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.graphImages = new Map<string, string>(); this.graphRelationIds = []; this.graphBranchIds = [];
      this.filterBranchIds = []; this.chatLines = [];
      await this.setupAssistant();
    }, '记录已恢复');
    this.backupMessage = this.error.length === 0 ? '记录已恢复，原有备份文件保留不变。' : '';
    if (this.error.length === 0) { this.updateStorage(); }
  }

  private async updateStorage(): Promise<void> {
    this.storageLabel = '正在统计…';
    try {
      if (this.files === null) { return; }
      const sizes = await this.files.storageStats();
      if (this.alive) { this.storageLabel = '已用 ' + formatBytes(sizes[0] + sizes[1]) + ' · 数据库 ' + formatBytes(sizes[0]) + ' · 附件 ' + formatBytes(sizes[1]); }
    } catch (_) { if (this.alive) { this.storageLabel = '空间统计暂不可用，可重新打开本页重试'; } }
  }

  @Builder
  feedback() {
    if (this.preview) {
      Text('界面预览 · 不保存数据').fontSize(12).fontColor(this.colors.primary).padding(10).width('100%').backgroundColor(this.colors.soft).borderRadius(10)
    }
    if (this.error.length > 0) {
      Text(this.error).fontSize(14).fontColor(this.colors.danger).width('100%').padding(12).backgroundColor(this.colors.card).borderRadius(10)
    } else if (this.notice.length > 0) {
      Text(this.notice).fontSize(13).fontColor(this.colors.primary).width('100%')
    }
    if (!this.ready && !this.busy) { Button('重新打开本地数据').onClick(() => this.initialize()).backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary) }
  }

  @Builder
  field(label: string) { Text(label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%') }

  @Builder
  empty(title: string, description: string) {
    Column({ space: 12 }) {
      Text(title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
      Text(description).fontSize(14).fontColor(this.colors.muted).textAlign(TextAlign.Center)
    }.width('100%').padding({ top: 36, bottom: 28 })
  }

  @Builder
  peopleList() {
    Column({ space: 10 }) {
      Search({ value: this.peopleSearch, placeholder: '搜索姓名或描述' }).backgroundColor(this.colors.card).borderRadius(10).fontColor(this.colors.text).placeholderColor(this.colors.muted).searchIcon({ color: this.colors.muted })
        .height(36)
        .margin(0)
        .id('people-search')
        .onFocus(() => this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE))
        .onBlur(() => this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE))
        .onChange((value: string) => { this.peopleSearch = value; })
      Text((this.peopleSearch.trim().length > 0 ? '找到 ' : '共 ') + this.people().length + ' 位人物').fontSize(12).fontColor(this.colors.muted).width('100%')
      if (this.people().length === 0) {
        this.empty(this.peopleSearch.trim().length > 0 ? '没有找到人物' : '还没有人物', this.peopleSearch.trim().length > 0 ? '试试其他姓名或描述。' : '添加姓名，也可以稍后补充关系。')
        ActionButton({ label: '新建人物', palette: this.colors, isEnabled: !this.busy && this.ready, onAction: () => this.editPerson() })
      } else {
        PageList({ tint: this.colors.muted }) {
          ForEach(this.people(), (person: Person) => {
            ListItem() {
              Row({ space: 14 }) {
                if (this.assetUri(person.avatarAssetId).length > 0) {
                  Image(this.assetUri(person.avatarAssetId)).width(48).height(48).borderRadius(16).objectFit(ImageFit.Cover)
                } else {
                  Text(person.name.slice(0, 1)).fontSize(23).fontColor(this.colors.primary).width(48).height(48)
                  .textAlign(TextAlign.Center).backgroundColor(this.colors.soft).borderRadius(16)
                }
                Column({ space: 7 }) {
                  Text(person.name).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.colors.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(person.description || '暂无备注').fontSize(13)
                    .fontColor(this.colors.muted).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Column({ space: 6 }) {
                  Text(this.relationSummary(person.id) || '未标记关系').fontSize(11).fontColor(this.colors.muted).maxLines(1)
                  Text(this.data.events.filter((card: EventCard) => card.personIds.includes(person.id)).length.toString() + ' 条记录').fontSize(11).fontColor(this.colors.muted)
                }.alignItems(HorizontalAlign.End).constraintSize({ maxWidth: 90 })
              }.padding({ top: 16, bottom: 16 }).width('100%')
                .border({ width: { bottom: 1 }, color: this.colors.border }).onClick(() => this.open('person', person.id))
            }
          }, (person: Person) => person.id + ':' + person.updatedAt)
        }
      }
    }.width('100%').layoutWeight(1)
  }

  @Builder
  personDetail(id: string) {
    PageScroll({ tint: this.colors.muted }) {
      Column({ space: 20 }) {
        if (this.assetUri(this.person(id)?.avatarAssetId ?? null).length > 0) {
          Image(this.assetUri(this.person(id)?.avatarAssetId ?? null)).width(100).height(100).borderRadius(50).objectFit(ImageFit.Cover)
            .onClick(() => this.openImage(this.assetUri(this.person(id)?.avatarAssetId ?? null)))
        } else {
          Text(this.personLabel(id).slice(0, 1)).fontSize(40).fontColor(this.colors.primary).width(100).height(100)
          .backgroundColor(this.colors.soft).textAlign(TextAlign.Center).borderRadius(50)
        }
        Text(this.personLabel(id)).fontSize(27).fontWeight(FontWeight.Bold).fontColor(this.colors.text)
        Text(this.person(id)?.description ?? '还没有写下人物描述').fontSize(16).fontColor(this.colors.muted).width('100%')
        this.field('人物关系')
        ForEach(this.data.edges.filter((edge: RelationEdge) => edge.personAId === id || edge.personBId === id), (edge: RelationEdge) => {
          Text(this.personLabel(edge.personAId === id ? edge.personBId : edge.personAId) + ' · ' +
            this.namedLabel(this.data.relations, [edge.relationId]) + ' · 强度 ' + (edge.strength ?? '未设置'))
            .fontSize(15).fontColor(this.colors.text).width('100%').padding(12).backgroundColor(this.colors.card).borderRadius(12)
        }, (edge: RelationEdge) => edge.id)
        if (this.person(id)?.deletedAt === null) {
          ActionButton({ label: '编辑人物与关系', palette: this.colors, isEnabled: !this.busy && this.ready, onAction: () => this.editPerson(id) })
        } else { Text('这位人物已从列表隐藏，历史记录仍保留。').fontSize(13).fontColor(this.colors.muted) }
        Button('查看关系与生活图谱').backgroundColor(this.colors.soft).fontColor(this.colors.primary).width('100%')
          .enabled(!this.busy && this.person(id)?.deletedAt === null)
          .onClick(() => { this.graphRelationIds = []; this.graphBranchIds = []; this.open('personGraph', id); })
        this.field('共同的生活记录')
        ForEach(this.data.events.filter((card: EventCard) => card.personIds.includes(id)), (card: EventCard) => { this.eventRow(card) }, (card: EventCard) => this.eventRowKey(card))
        if (this.person(id)?.deletedAt === null) {
          Button('删除人物').backgroundColor(Color.Transparent).fontColor(this.colors.danger).onClick(() => this.confirmDeletePerson(id))
        }
      }.width('100%').padding({ bottom: 24 })
    }
  }

  @Builder
  personEditor() {
    PageScroll({ tint: this.colors.muted }) {
      Column({ space: 16 }) {
        if (this.assetUri(this.personAvatarId).length > 0) { Image(this.assetUri(this.personAvatarId)).width(80).height(80).borderRadius(40).objectFit(ImageFit.Cover) }
        Button('选择头像').backgroundColor(this.colors.soft).fontColor(this.colors.primary).onClick(() => this.pickMedia('image', 'person'))
        this.field('姓名 *')
        TextInput({ text: this.personName, placeholder: '怎么称呼这个人？' }).fontColor(this.colors.text).backgroundColor(this.colors.card).placeholderColor(this.colors.muted).caretColor(this.colors.primary)
          .height(52).enabled(!this.busy).onChange((value: string) => { this.personName = value; })
        this.field('关于这个人')
        TextArea({ text: this.personBio, placeholder: '你们如何相识？有什么想记住的事？' }).height(140).fontColor(this.colors.text).placeholderColor(this.colors.muted).caretColor(this.colors.primary)
          .backgroundColor(this.colors.card).enabled(!this.busy).onChange((value: string) => { this.personBio = value; })
        this.field('与其他人的关系')
        Button('管理关系类型').fontSize(13).backgroundColor(this.colors.soft).fontColor(this.colors.primary).enabled(!this.busy).onClick(() => this.openTags('relations'))
        ForEach(this.relationInputs, (input: RelationEditorItem) => {
          RelationEditorRow({ item: input, people: this.data.persons.filter((person: Person) => person.id !== this.personId && (person.deletedAt === null || person.id === input.targetPersonId)),
            relations: this.data.relations, palette: this.colors, disabled: this.busy,
            onRemove: (rowId: string) => { this.relationInputs = this.relationInputs.filter((item: RelationEditorItem) => item.rowId !== rowId); } })
        }, (input: RelationEditorItem) => input.rowId)
        Button('＋ 添加关系').backgroundColor(this.colors.soft).fontColor(this.colors.primary).onClick(() => this.addRelation())
        ActionButton({ label: this.busy ? '正在保存…' : '保存人物', palette: this.colors, isEnabled: !this.busy && this.ready, onAction: () => this.savePerson() })
        Button('取消').width('100%').backgroundColor(this.colors.soft).fontColor(this.colors.text).enabled(!this.busy).onClick(() => this.goBack())
      }.width('100%').padding({ bottom: 28 }).enabled(!this.busy)
    }
  }

  @Builder
  eventRow(card: EventCard) {
    Row({ space: 14 }) {
      Column({ space: 5 }) {
        Text(formatDate(card.event.occurredAt).slice(8, 10)).fontSize(25).fontColor(this.colors.primary)
        Text(formatDate(card.event.occurredAt).slice(0, 7).replace('-', '/')).fontSize(10).fontColor(this.colors.muted)
      }.width(44).alignItems(HorizontalAlign.Start)
      Column({ space: 8 }) {
        Text(card.event.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%').maxLines(2)
        if (card.event.content.length > 0) { Text(card.event.content).fontSize(14).lineHeight(22).fontColor(this.colors.muted).maxLines(2).width('100%').textOverflow({ overflow: TextOverflow.Ellipsis }) }
        Text(card.personIds.map((id: string) => this.personLabel(id)).join('、')).fontSize(12).fontColor(this.colors.muted).width('100%').maxLines(2)
        Row({ space: 7 }) {
          Row() {}.width(6).height(6).backgroundColor(card.event.color).borderRadius(3)
          Text(this.namedLabel(this.data.branches, card.branchIds)).fontSize(11).fontColor(this.colors.muted).layoutWeight(1).maxLines(1)
          Text(this.namedLabel(this.data.emotions, card.emotionIds)).fontSize(11).fontColor(this.colors.primary).maxLines(1)
        }.width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.alignItems(VerticalAlign.Top).padding({ top: 18, bottom: 18 }).width('100%')
      .border({ width: { bottom: 1 }, color: this.colors.border }).onClick(() => this.open('event', card.event.id))
  }

  @Builder
  eventsList() {
    Column({ space: 10 }) {
      Search({ value: this.eventSearch, placeholder: '搜索生活记录' }).backgroundColor(this.colors.card).borderRadius(10).fontColor(this.colors.text).placeholderColor(this.colors.muted).searchIcon({ color: this.colors.muted })
        .height(36)
        .margin(0)
        .id('events-search')
        .onFocus(() => this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE))
        .onBlur(() => this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE))
        .onChange((value: string) => {
          this.eventSearch = value;
          this.timelineExpandedEventIds = [];
          this.resetTimelineFolds();
        })
      Row({ space: 8 }) {
        Blank()
        Select(this.timelinePersonOptions()).selected(this.timelinePersonIndex()).value(this.timelinePersonLabel())
          .fontColor(this.colors.text).backgroundColor(this.colors.card)
          .optionHeight(320)
          .optionFontColor(this.colors.text).optionBgColor(this.colors.card)
          .selectedOptionFontColor(this.colors.onPrimary).selectedOptionBgColor(this.colors.primary)
          .constraintSize({ minWidth: 112, maxWidth: 150 }).id('timeline-person')
          .onSelect((selected: number) => this.setTimelinePerson(selected))
        Button('⇅', { type: ButtonType.Normal }).width(38).height(38).padding(0).fontSize(20)
          .fontColor(this.colors.primary).backgroundColor(this.colors.soft).borderRadius(10)
          .accessibilityText(this.timelineAscending ? '当前最早在上，点按改为最近在上' : '当前最近在上，点按改为最早在上')
          .id('timeline-order').onClick(() => this.toggleTimelineOrder())
      }.width('100%').alignItems(VerticalAlign.Center)
      Scroll() {
        Row({ space: 20 }) {
          FilterTab({ label: '全部', selected: this.filterBranchIds.length === 0, palette: this.colors, disabled: this.busy, controlId: 'event-filter-all', onAction: () => { this.filterBranchIds = []; this.timelineExpandedEventIds = []; this.resetTimelineFolds(); } })
          ForEach(this.data.branches, (item: NamedItem) => { FilterTab({ label: item.name, selected: this.filterBranchIds.includes(item.id), palette: this.colors, disabled: this.busy, controlId: 'event-filter-' + item.id, onAction: () => { this.filterBranchIds = toggled(this.filterBranchIds, item.id); this.timelineExpandedEventIds = []; this.resetTimelineFolds(); } }) }, (item: NamedItem) => item.id)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      Row() {
        Text((this.timelineAscending ? '最早在上' : '最近在上') + ' · ' + this.timelineCards().length + ' 件事')
          .fontSize(11).fontColor(this.colors.muted)
      }.width('100%')
      .justifyContent(FlexAlign.End)
      if (this.timelineCards().length === 0) {
        if (this.eventSearch.trim().length > 0 || this.filterBranchIds.length > 0 || this.timelinePersonId.length > 0) {
          this.empty('没有找到记录', '试试其他关键词、人物或生活分支。')
          Button('清除筛选').fontSize(13).fontColor(this.colors.primary).backgroundColor(this.colors.soft)
            .onClick(() => { this.eventSearch = ''; this.filterBranchIds = []; this.timelinePersonId = ''; this.resetTimelineFolds(); })
        } else {
          this.empty('从一件小事开始', '点底部的＋记一件事，时间会慢慢长成自己的枝干。')
        }
      } else {
        PageList({ space: 6, tint: this.colors.muted }) {
          ForEach(this.timelineGroups(), (group: TimelineEventGroup) => {
            ListItem() {
              TimelineGroupSection({ group: group, palette: this.colors, people: this.data.persons, branches: this.data.branches,
                emotions: this.data.emotions, expanded: !this.timelineCollapsedGroupKeys.includes(group.key),
                expandedEventIds: this.timelineExpandedEventIds, disabled: this.busy,
                onToggleGroup: (key: string) => this.toggleTimelineGroup(key), onToggleEvent: (id: string) => this.toggleTimelineEvent(id),
                onOpenEvent: (id: string) => this.open('event', id) })
            }
          }, (group: TimelineEventGroup) => group.key + ':' + group.events.map((card: EventCard) => this.eventRowKey(card)).join(','))
        }
      }
    }.width('100%').layoutWeight(1)
  }

  @Builder
  eventEditor() {
    PageScroll({ tint: this.colors.muted }) {
      Column({ space: 17 }) {
        this.field('事件标题 *')
        TextInput({ text: this.eventTitle, placeholder: '今天发生了什么？' }).height(50).fontColor(this.colors.text).backgroundColor(this.colors.card).placeholderColor(this.colors.muted).caretColor(this.colors.primary)
          .id('event-title')
          .onChange((value: string) => { this.eventTitle = value; })
        this.field('生活记录')
        TextArea({ text: this.eventContent, placeholder: '记下当时的心情与细节…' }).height(180).fontColor(this.colors.text).backgroundColor(this.colors.card).placeholderColor(this.colors.muted).caretColor(this.colors.primary)
          .onChange((value: string) => { this.eventContent = value; })
        this.field('发生日期 *')
        Button(formatDate(this.eventDate) + '  ›').width('100%').backgroundColor(this.colors.card).fontColor(this.colors.text)
          .id('event-date').onClick(() => this.chooseDate())
        this.field('地点')
        TextInput({ text: this.eventLocation, placeholder: '在哪里？（可选）' }).fontColor(this.colors.text).backgroundColor(this.colors.card).placeholderColor(this.colors.muted).caretColor(this.colors.primary)
          .onChange((value: string) => { this.eventLocation = value; })
        this.field('参与者 *')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.eventParticipants(), (person: Person) => {
            Row() { ChoiceChip({ label: this.personLabel(person.id), selected: this.participantIds.includes(person.id), palette: this.colors, disabled: this.busy, controlId: 'event-person-' + person.id, onAction: () => { this.participantIds = toggled(this.participantIds, person.id); } }) }.margin({ right: 8, bottom: 8 })
          }, (person: Person) => person.id)
        }
        this.field('生活分支')
        Button('管理生活分支').fontSize(13).backgroundColor(this.colors.soft).fontColor(this.colors.primary).enabled(!this.recording).onClick(() => this.openTags('branches'))
        Flex({ wrap: FlexWrap.Wrap }) {
          Row() { ChoiceChip({ label: '未设置', selected: this.branchIds.length === 0, palette: this.colors, disabled: this.busy, onAction: () => { this.branchIds = []; } }) }.margin({ right: 8, bottom: 8 })
          ForEach(this.data.branches, (item: NamedItem) => {
            Row() { ChoiceChip({ label: item.name, selected: this.branchIds.includes(item.id), palette: this.colors, disabled: this.busy, controlId: 'event-branch-' + item.id, onAction: () => { this.branchIds = toggled(this.branchIds, item.id); } }) }.margin({ right: 8, bottom: 8 })
          }, (item: NamedItem) => item.id)
        }
        this.field('情绪')
        Button('管理情绪标签').fontSize(13).backgroundColor(this.colors.soft).fontColor(this.colors.primary).enabled(!this.recording).onClick(() => this.openTags('emotions'))
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.data.emotions, (item: NamedItem) => {
            Row() { ChoiceChip({ label: item.name, selected: this.emotionIds.includes(item.id), palette: this.colors, disabled: this.busy, controlId: 'event-emotion-' + item.id, onAction: () => { this.emotionIds = toggled(this.emotionIds, item.id); } }) }.margin({ right: 8, bottom: 8 })
          }, (item: NamedItem) => item.id)
        }
        this.field('事件颜色')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.eventColors(), (color: string) => {
            Button(this.eventColor === color ? '✓' : '').width(38).height(38).padding(0).backgroundColor(color).fontColor(Color.White)
              .id('event-color-' + color).accessibilitySelected(this.eventColor === color)
              .margin({ right: 10, bottom: 8 }).onClick(() => { this.eventColor = color; })
          })
        }
        this.field('图片与语音')
        EventAttachments({ assets: this.eventAssets, editable: true, disabled: this.busy, palette: this.colors,
          mediaRoot: this.files?.directory() ?? '', onImage: (uri: string) => this.openImage(uri),
          onCover: (id: string) => this.setEventCover(id),
          onRemove: (id: string) => { this.eventAssets = this.eventAssets.filter((asset: MediaAsset) => asset.id !== id); } })
        Row({ space: 8 }) {
          Button('添加图片').fontSize(13).backgroundColor(this.colors.soft).fontColor(this.colors.primary).enabled(!this.recording).id('event-pick-image').onClick(() => this.pickMedia('image'))
          Button('导入音频').fontSize(13).backgroundColor(this.colors.soft).fontColor(this.colors.primary).enabled(!this.recording).id('event-pick-audio').onClick(() => this.pickMedia('audio'))
          Button(this.recording ? '停止 ' + this.recordingSeconds + '秒' : '录音').fontSize(13).backgroundColor(this.recording ? this.colors.danger : this.colors.primary)
            .fontColor(this.recording ? this.colors.onDanger : this.colors.onPrimary)
            .onClick(() => { if (this.recording) { this.stopRecording(); } else { this.startRecording(); } })
        }
        ActionButton({ label: this.busy ? '正在保存…' : '保存事件', palette: this.colors, isEnabled: !this.busy && this.ready, onAction: () => this.saveEvent() })
        Button('取消').backgroundColor(this.colors.soft).fontColor(this.colors.text).enabled(!this.busy).onClick(() => this.goBack())
      }.width('100%').padding({ bottom: 32 }).enabled(!this.busy)
    }
  }

  @Builder
  eventDetail(id: string) {
    PageScroll({ tint: this.colors.muted }) {
      Column({ space: 18 }) {
        ForEach(this.data.events.filter((card: EventCard) => card.event.id === id), (card: EventCard) => {
          Text(card.event.title).fontSize(27).fontWeight(FontWeight.Bold).fontColor(this.colors.text).width('100%')
          Text(formatDate(card.event.occurredAt) + (card.event.locationText.length > 0 ? ' · ' + card.event.locationText : '')).fontSize(13).fontColor(this.colors.muted).width('100%')
          Text(card.event.content || '没有补充文字').fontSize(17).lineHeight(27).fontColor(this.colors.text).width('100%').copyOption(CopyOptions.LocalDevice)
          EventAttachments({ assets: card.assets, palette: this.colors, mediaRoot: this.files?.directory() ?? '',
            onImage: (uri: string) => this.openImage(uri) })
          this.field('参与者')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(card.personIds, (personId: string) => {
              Row() { ChoiceChip({ label: this.personLabel(personId), selected: false, palette: this.colors, disabled: this.busy, onAction: () => { if (personId === this.data.profile.defaultPersonId) { this.editProfile(); } else { this.open('person', personId); } } }) }.margin({ right: 8, bottom: 8 })
            })
          }
          Text(this.namedLabel(this.data.branches, card.branchIds) + '   ' + this.namedLabel(this.data.emotions, card.emotionIds)).fontSize(14).fontColor(this.colors.primary).width('100%')
          ActionButton({ label: '编辑事件', palette: this.colors, isEnabled: !this.busy && this.ready, onAction: () => this.editEvent(id) })
          Button('删除事件').backgroundColor(Color.Transparent).fontColor(this.colors.danger).onClick(() => this.confirmDeleteEvent(id))
        })
      }.width('100%').padding({ bottom: 28 }).enabled(!this.busy)
    }
  }

  @Builder
  tagsPage() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.tagName, placeholder: this.tagId.length > 0 ? '修改名称' : '新建分类名称' }).layoutWeight(1).placeholderColor(this.colors.muted).caretColor(this.colors.primary)
          .fontColor(this.colors.text).backgroundColor(this.colors.card).onChange((value: string) => { this.tagName = value; })
        Button(this.tagId.length > 0 ? '保存' : '添加').backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary).enabled(!this.busy).onClick(() => this.saveTag())
      }
      if (this.tagId.length > 0) { Button('取消重命名').onClick(() => { this.tagName = ''; this.tagId = ''; }).backgroundColor(this.colors.soft).fontColor(this.colors.text) }
      PageList({ space: 10, tint: this.colors.muted }) {
        ForEach(this.tags(), (item: NamedItem) => {
          ListItem() {
            Row({ space: 12 }) {
              Text(item.name).fontSize(17).fontColor(this.colors.text).layoutWeight(1).onClick(() => { this.tagId = item.id; this.tagName = item.name; })
              Button('删除').fontColor(this.colors.danger).backgroundColor(Color.Transparent).onClick(() => {
                this.getUIContext().showAlertDialog({ title: '删除“' + item.name + '”？', message: '移除分类及其关联，保留人物和事件本身。',
                  primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '删除', action: () => {
                    this.removeTag(item.id);
                  } } });
              })
            }.padding(14).backgroundColor(this.colors.card).borderRadius(14).width('100%')
          }
        }, (item: NamedItem) => item.id + ':' + item.name)
      }
    }.layoutWeight(1).width('100%').enabled(!this.busy)
  }

  @Builder
  menu(label: string, action: () => void) {
    Row() {
      Text(label).fontSize(16).fontColor(this.colors.text).layoutWeight(1)
      Text('›').fontSize(25).fontColor(this.colors.muted)
    }.padding(17).width('100%').backgroundColor(this.colors.card).borderRadius(14).onClick(action)
  }

  @Builder
  profilePage() {
    PageScroll({ tint: this.colors.muted }) {
      Column({ space: 18 }) {
        if (this.assetUri(this.self()?.avatarAssetId ?? null).length > 0) {
          Image(this.assetUri(this.self()?.avatarAssetId ?? null)).width(112).height(112).borderRadius(56).objectFit(ImageFit.Cover).onClick(() => this.editProfile())
        } else {
          Text(this.data.profile.displayName.slice(0, 1)).fontSize(45).fontColor(this.colors.primary).width(112).height(112)
          .textAlign(TextAlign.Center).backgroundColor(this.colors.soft).borderRadius(56).onClick(() => this.editProfile())
        }
        Text(this.data.profile.displayName).fontSize(27).fontWeight(FontWeight.Bold).fontColor(this.colors.text)
        if ((this.self()?.description ?? '').length > 0) { Text(this.self()?.description ?? '').fontSize(14).fontColor(this.colors.muted).textAlign(TextAlign.Center) }
        Row({ space: 12 }) {
          Column({ space: 5 }) { Text((this.participants().length - 1).toString()).fontSize(30).fontColor(this.colors.primary); Text('人物').fontSize(13).fontColor(this.colors.muted) }
            .layoutWeight(1).padding(18).backgroundColor(this.colors.card).borderRadius(18).onClick(() => this.open('people'))
          Column({ space: 5 }) { Text(this.data.events.length.toString()).fontSize(30).fontColor(this.colors.primary); Text('事件').fontSize(13).fontColor(this.colors.muted) }
            .layoutWeight(1).padding(18).backgroundColor(this.colors.card).borderRadius(18).onClick(() => { this.filterBranchIds = []; this.open('events'); })
        }.width('100%')
        this.menu('个人资料', () => this.editProfile())
        this.menu('关系类型', () => this.openTags('relations'))
        this.menu('生活分支', () => this.openTags('branches'))
        this.menu('生活分支图谱', () => { this.graphBranchIds = []; this.open('branchGraph'); })
        this.menu('情绪标签', () => this.openTags('emotions'))
        this.menu('外观与主题', () => this.open('appearance'))
        this.menu('桌面关系卡片', () => this.openCardSettings())
        this.menu('AI 生活助手', () => { this.open('ai'); this.scrollChat(); })
        this.menu('本地备份与恢复', () => { this.backupMessage = ''; this.open('backup'); this.updateStorage(); })
        Text('本机记录 · 无需登录').fontSize(12).fontColor(this.colors.muted).padding(12)
      }.width('100%').padding({ bottom: 24, top: 8 }).enabled(!this.busy)
    }
  }

  @Builder
  profileEditor() {
    PageScroll({ tint: this.colors.muted }) {
      Column({ space: 18 }) {
        if (this.assetUri(this.profileAvatarId).length > 0) { Image(this.assetUri(this.profileAvatarId)).width(90).height(90).borderRadius(45).objectFit(ImageFit.Cover) }
        Button('选择我的头像').backgroundColor(this.colors.soft).fontColor(this.colors.primary).onClick(() => this.pickMedia('image', 'profile'))
        this.field('你的称呼')
        TextInput({ text: this.profileName }).maxLength(24).backgroundColor(this.colors.card).fontColor(this.colors.text).onChange((value: string) => { this.profileName = value; }).placeholderColor(this.colors.muted).caretColor(this.colors.primary)
        this.field('个人见解')
        TextArea({ text: this.profileBio, placeholder: '写一句关于自己的话…' }).maxLength(200).height(130).backgroundColor(this.colors.card).fontColor(this.colors.text).onChange((value: string) => { this.profileBio = value; }).placeholderColor(this.colors.muted).caretColor(this.colors.primary)
        this.field('生日')
        Button(this.profileBirthday || '选择生日（可选）').fontColor(this.colors.text).backgroundColor(this.colors.card).onClick(() => {
          this.getUIContext().showDatePickerDialog({ selected: this.profileBirthday.length > 0 ? new Date(this.profileBirthday) : new Date(),
            start: new Date(1900, 0, 1), end: new Date(),
            onDateAccept: (date: Date) => { this.profileBirthday = formatDate(date.getTime()); } });
        })
        Button('清除生日').fontSize(13).backgroundColor(Color.Transparent).fontColor(this.colors.muted).onClick(() => { this.profileBirthday = ''; })
        ActionButton({ label: '保存资料', palette: this.colors, isEnabled: !this.busy && this.ready, onAction: () => this.saveProfile() })
      }.width('100%').padding({ bottom: 28 }).enabled(!this.busy)
    }
  }

  @Builder
  appearancePage() {
    Column({ space: 20 }) {
      this.field('主题色')
      Row({ space: 10 }) {
        ChoiceChip({ label: '森林', selected: this.data.profile.themeKey === 'forest', palette: this.colors, disabled: this.busy, onAction: () => this.appearance('forest', this.data.profile.appearance) })
        ChoiceChip({ label: '海洋', selected: this.data.profile.themeKey === 'ocean', palette: this.colors, disabled: this.busy, onAction: () => this.appearance('ocean', this.data.profile.appearance) })
        ChoiceChip({ label: '日落', selected: this.data.profile.themeKey === 'sunset', palette: this.colors, disabled: this.busy, onAction: () => this.appearance('sunset', this.data.profile.appearance) })
        ChoiceChip({ label: '极简', selected: this.data.profile.themeKey === 'minimal', palette: this.colors, disabled: this.busy, onAction: () => this.appearance('minimal', this.data.profile.appearance) })
      }
      this.field('显示模式')
      Row({ space: 10 }) {
        ChoiceChip({ label: '跟随系统', selected: this.data.profile.appearance === 'system', palette: this.colors, disabled: this.busy, onAction: () => this.appearance(this.data.profile.themeKey, 'system') })
        ChoiceChip({ label: '浅色', selected: this.data.profile.appearance === 'light', palette: this.colors, disabled: this.busy, onAction: () => this.appearance(this.data.profile.themeKey, 'light') })
        ChoiceChip({ label: '深色', selected: this.data.profile.appearance === 'dark', palette: this.colors, disabled: this.busy, onAction: () => this.appearance(this.data.profile.themeKey, 'dark') })
      }
      Text('外观保存在本机，重新打开后会恢复。').fontSize(13).fontColor(this.colors.muted)
      this.field('自定义事件颜色')
      Row({ space: 10 }) {
        TextInput({ text: this.newColor, placeholder: '#5B8C5A' }).layoutWeight(1).backgroundColor(this.colors.card).fontColor(this.colors.text).placeholderColor(this.colors.muted).caretColor(this.colors.primary)
          .onChange((value: string) => { this.newColor = value; })
        Button('添加').backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary).onClick(() => this.saveColors())
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.data.profile.customEventColors, (color: string) => {
          Button(color + ' ×').fontSize(12).backgroundColor(color).fontColor(Color.White).margin(4).onClick(() => this.saveColors(color))
        })
      }
    }.width('100%').layoutWeight(1).enabled(!this.busy)
  }

  @Builder
  aiEntrySheet() {
    AssistantEntrySheet({ kind: this.aiEntryKind, people: this.data.persons, selfId: this.data.profile.defaultPersonId, palette: this.colors,
      onClose: () => { this.aiEntryOpen = false; }, onStart: (request: AssistantEntryRequest) => this.startAssistantEntry(request) })
  }

  @Builder
  aiEntry(label: string, icon: Resource, kind: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 16 }) {
        Image(icon).width(22).height(22).fillColor(this.colors.primary)
        Text(label).fontSize(16).fontColor(this.colors.text).layoutWeight(1).textAlign(TextAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([this.colors.muted])
      }.width('100%')
    }.width('100%').height(62).padding({ left: 2, right: 2 }).borderRadius(0).backgroundColor(Color.Transparent)
      .border({ width: { bottom: 1 }, color: this.colors.border }).enabled(this.aiReady && !this.aiBusy && !this.aiSwitching && !this.busy)
      .id('ai-entry-' + kind).accessibilityText(label).onClick(() => { this.aiEntryKind = kind; this.aiEntryOpen = true; })
  }

  @Builder
  aiPage() {
    Column({ space: 8 }) {
      Row() {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.clock')).fontSize(18).fontColor([this.colors.primary])
            Text('历史聊天').fontSize(14).fontColor(this.colors.text)
          }
        }.height(44).padding({ left: 0, right: 12 }).backgroundColor(Color.Transparent)
          .enabled(!this.busy && !this.aiSwitching).id('ai-history').onClick(() => this.openAssistantHistory())
        Blank()
        Button('＋ 新聊天', { type: ButtonType.Normal }).height(44).fontSize(14).padding({ left: 12, right: 0 })
          .backgroundColor(Color.Transparent).fontColor(this.chatLines.length > 0 || this.aiHistory.activeId.length > 0 ? this.colors.primary : this.colors.muted)
          .enabled(!this.busy && !this.aiSwitching && (this.chatLines.length > 0 || this.aiHistory.activeId.length > 0))
          .id('ai-new-chat').onClick(() => this.switchAssistantChat(''))
      }.width('100%').flexShrink(0)
      if (!this.aiConfigured) {
        Button({ type: ButtonType.Normal }) {
          Row() {
            Text('连接 AI 服务后，即可开始').fontSize(13).fontColor(this.colors.primary).layoutWeight(1).textAlign(TextAlign.Start)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([this.colors.primary])
          }.width('100%')
        }.width('100%').height(44).borderRadius(12).backgroundColor(this.colors.soft).padding({ left: 14, right: 14 })
          .enabled(!this.aiBusy && !this.busy).id('ai-connect-service').onClick(() => this.openAISettings())
      }
      if (this.aiError.length > 0) { Text(this.aiError).fontSize(13).fontColor(this.colors.danger).width('100%').copyOption(CopyOptions.LocalDevice) }
      PageList({ space: 14, scroller: this.aiScroller, tint: this.colors.muted }) {
        if (this.chatLines.length > this.aiVisibleCount) {
          ListItem() {
            Button('查看更早的聊天（还有' + (this.chatLines.length - this.aiVisibleCount).toString() + '条）').fontSize(13)
              .fontColor(this.colors.primary).backgroundColor(this.colors.soft).width('100%').onClick(() => { this.aiVisibleCount += 40; })
          }
        }
        if (this.chatLines.length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              Text('想回顾哪段经历？').fontSize(24).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%')
              Text('找回共同经历，回顾关系变化。').fontSize(14).fontColor(this.colors.muted).width('100%')
              Column() {
                this.aiEntry('回顾共同经历', $r('app.media.nav_people'), 'together')
                this.aiEntry('找一段往事', $r('app.media.nav_search'), 'memory')
                this.aiEntry('看看最近的生活', $r('app.media.nav_records'), 'recent')
              }.width('100%').margin({ top: 20 })
            }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 28, bottom: 12 })
          }
        }
        ForEach(this.chatLines.slice(-this.aiVisibleCount), (line: AssistantTurn) => {
          ListItem() {
            AssistantBubble({ turn: line, palette: this.colors, onCopy: (text: string) => this.copyAnswer(text),
              onRetry: (text: string) => { if (!this.aiBusy && !this.aiSwitching) { this.question = text; this.aiScope = line.scope; this.draftChanged(); } },
              onLink: (url: string, refs: AssistantReference[]) => this.assistantLink(url, refs) })
          }
        }, (line: AssistantTurn) => line.id + ':' + line.status)
        if (this.aiBusy) { ListItem() { Text(this.aiStatus || '正在查询你的生活记录…').fontSize(14).fontColor(this.colors.muted).padding(12) } }
      }
      Column({ space: 2 }) {
        Row() {
          Button('AI 服务', { type: ButtonType.Normal }).fontSize(12).height(24).padding({ left: 2, right: 12, top: 0, bottom: 0 })
            .fontColor(this.colors.muted).backgroundColor(Color.Transparent).enabled(!this.aiBusy && !this.aiSwitching && !this.busy)
            .id('ai-service-settings').onClick(() => this.openAISettings())
          Blank()
          if (this.chatLines.length > 0 || this.aiError.length > 0) {
            Button('删除聊天', { type: ButtonType.Normal }).fontSize(12).height(24).padding({ left: 12, right: 2, top: 0, bottom: 0 })
              .fontColor(this.colors.muted).backgroundColor(Color.Transparent).enabled(!this.busy && !this.aiSwitching && (this.aiReady || this.aiError.length > 0))
              .id('ai-clear').onClick(() => this.clearConversation())
          }
        }.width('100%').height(24)
        Row({ space: 8 }) {
          TextInput({ text: this.question, placeholder: this.chatLines.length > 0 ? '继续这段聊天…' : '输入人物、时间或记得的片段…' }).layoutWeight(1).height(48).fontSize(15)
            .fontColor(this.colors.text).backgroundColor(Color.Transparent).placeholderColor(this.colors.muted).caretColor(this.colors.primary)
            .id('ai-question').maxLength(6000).enterKeyType(EnterKeyType.Send)
            .enabled(!this.aiBusy && !this.aiSwitching && this.aiReady).onChange((value: string) => {
              if (value !== this.question) { this.aiScope = undefined; this.question = value; this.draftChanged(); }
            })
            .onEditChange((editing: boolean) => { this.aiEditing = editing; }).onSubmit(() => this.askAI())
          if (this.aiBusy) {
            Button('停止').backgroundColor(this.colors.soft).fontColor(this.colors.text).id('ai-stop').onClick(() => this.assistant?.cancel())
          } else {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(18)
                .fontColor([this.aiReady && !this.busy && this.question.trim().length > 0 ? this.colors.onPrimary : this.colors.muted])
            }.width(36).height(36).padding(0).backgroundColor(this.aiReady && !this.busy && this.question.trim().length > 0 ? this.colors.primary : this.colors.soft)
              .enabled(this.aiReady && !this.busy && !this.aiSwitching && this.question.trim().length > 0)
              .id('ai-send').accessibilityText('发送').onClick(() => this.askAI())
          }
        }.padding({ right: 6 }).width('100%').height(48).flexShrink(0).backgroundColor(this.colors.card).borderRadius(24)
      }.width('100%').flexShrink(0)
    }.width('100%').layoutWeight(1)
      .bindSheet($$this.aiEntryOpen, this.aiEntrySheet, { height: SheetSize.FIT_CONTENT, showClose: false, dragBar: true,
        backgroundColor: this.colors.paper, maskColor: '#66000000', enableOutsideInteractive: false })
  }

  @Builder
  backupPage() {
    Column({ space: 20 }) {
      Text('把生活记录带在自己手里').fontSize(23).fontWeight(FontWeight.Medium).fontColor(this.colors.text).width('100%')
      Text('备份包含人物、关系、事件、图片、语音、个人设置和聊天记录。').fontSize(15).fontColor(this.colors.muted).width('100%')
      Text('AI 服务配置和密钥不包含在备份中，换设备后需重新填写。').fontSize(12).fontColor(this.colors.muted).width('100%')
      Text('当前人物 ' + this.participants().filter((person: Person) => person.id !== this.data.profile.defaultPersonId).length + ' 位 · 事件 ' + this.data.events.length + ' 条').fontSize(14).fontColor(this.colors.primary).width('100%')
      Text(this.storageLabel).fontSize(13).fontColor(this.colors.muted).width('100%')
      ActionButton({ label: '导出备份', palette: this.colors, isEnabled: !this.busy && this.ready, onAction: () => this.exportBackup() })
      Button('选择备份并恢复').width('100%').height(50).backgroundColor(this.colors.soft).fontColor(this.colors.text).enabled(!this.busy).onClick(() => this.chooseBackup())
      if (this.backupMessage.length > 0) { Text(this.backupMessage).fontSize(14).fontColor(this.colors.primary).width('100%') }
      Text('仅支持此鸿蒙版导出的备份。当前上限：总计 1GB、单附件 512MB、清单 16MB。恢复前会展示记录数量并再次确认。')
        .fontSize(12).fontColor(this.colors.muted).width('100%').lineHeight(20)
      Blank()
    }.width('100%').layoutWeight(1)
  }

  @Builder
  searchPage() {
    Column({ space: 14 }) {
      Search({ value: this.search, placeholder: '搜索人物、生活记录' }).height(36).margin(0).backgroundColor(this.colors.card).fontColor(this.colors.text).placeholderColor(this.colors.muted).searchIcon({ color: this.colors.muted })
        .onChange((value: string) => { this.search = value; })
      Row({ space: 10 }) {
        ChoiceChip({ label: '人物', selected: this.searchKind === 0, palette: this.colors, disabled: this.busy, onAction: () => { this.searchKind = 0; } })
        ChoiceChip({ label: '事件', selected: this.searchKind === 1, palette: this.colors, disabled: this.busy, onAction: () => { this.searchKind = 1; } })
      }.width('100%')
      if (this.search.trim().length === 0) { this.empty('查找人物或记录', '输入人物姓名、描述或事件内容。'); Blank() }
      else {
        PageList({ space: 12, tint: this.colors.muted }) {
          if (this.searchKind === 0) {
            ForEach(this.people(true), (person: Person) => {
              ListItem() { this.menu(person.name, () => this.open('person', person.id)) }
            }, (person: Person) => person.id + ':' + person.updatedAt)
            if (this.people(true).length === 0) { ListItem() { this.empty('没有找到人物', '试试其他关键词。') } }
          } else {
            ForEach(this.events(true), (card: EventCard) => { ListItem() { this.eventRow(card) } }, (card: EventCard) => this.eventRowKey(card))
            if (this.events(true).length === 0) { ListItem() { this.empty('没有找到记录', '试试其他关键词。') } }
          }
        }
      }
    }.layoutWeight(1).width('100%')
  }

  @Builder
  homePage() {
    Column({ space: 10 }) {
      Scroll() {
        Row({ space: 20 }) {
          if (this.homeBranchGraph) {
            FilterTab({ label: '全部分支', selected: this.graphBranchIds.length === 0, palette: this.colors, disabled: this.busy, controlId: 'home-graph-branch-all', onAction: () => { this.graphBranchIds = []; } })
            ForEach(this.data.branches, (item: NamedItem) => {
              FilterTab({ label: item.name, selected: this.graphBranchIds.includes(item.id), palette: this.colors, disabled: this.busy, controlId: 'home-graph-branch-' + item.id, onAction: () => { this.graphBranchIds = toggled(this.graphBranchIds, item.id); } })
            }, (item: NamedItem) => item.id)
          } else {
            FilterTab({ label: '全部关系', selected: this.graphRelationIds.length === 0, palette: this.colors, disabled: this.busy, controlId: 'graph-relation-all', onAction: () => { this.graphRelationIds = []; } })
            ForEach(this.data.relations, (item: NamedItem) => {
              FilterTab({ label: item.name, selected: this.graphRelationIds.includes(item.id), palette: this.colors, disabled: this.busy, controlId: 'graph-relation-' + item.id, onAction: () => { this.graphRelationIds = toggled(this.graphRelationIds, item.id); } })
            }, (item: NamedItem) => item.id)
          }
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      Stack({ alignContent: Alignment.BottomStart }) {
        if (this.preview) {
          Column() {
            this.empty(this.homeBranchGraph ? '生活分支图谱' : '关系图', '实际运行时显示可拖动的小球与连线。')
            Blank()
          }.width('100%').height('100%')
        } else {
          NativeGraph({ payload: this.graphPayload(this.homeBranchGraph ? 'branch' : 'home', this.data.profile.defaultPersonId), theme: this.graphTheme(), paperColor: this.colors.paper, palette: this.colors,
          onPerson: (id: string) => this.graphPerson(id), onEvent: (id: string) => this.open('event', id) })
          .width('100%').height('100%')
        }
        Button(this.homeBranchGraph ? '⇄ 人际' : '⇄ 生活', { type: ButtonType.Normal })
          .fontSize(12).height(32).padding({ left: 12, right: 12 }).borderRadius(12)
          .fontColor(this.colors.primary).backgroundColor('#14' + this.colors.primary.substring(1))
          .border({ width: 1, color: '#40' + this.colors.primary.substring(1) })
          .margin({ left: 0, bottom: 8 }).id('home-graph-switch').enabled(!this.busy)
          .accessibilityText(this.homeBranchGraph ? '切换到人际关系图谱' : '切换到生活分支图谱')
          .onClick(() => { this.homeBranchGraph = !this.homeBranchGraph; })
      }.width('100%').layoutWeight(1)
      if (!this.homeBranchGraph && this.data.persons.filter((person: Person) => person.deletedAt === null && person.id !== this.data.profile.defaultPersonId).length === 0) {
        Row({ space: 10 }) {
          Text('添加人物和关系后，在这里查看联系。').fontSize(12).fontColor(this.colors.muted).layoutWeight(1)
          Button('添加人物', { type: ButtonType.Normal }).fontSize(12).height(38).fontColor(this.colors.primary).backgroundColor(Color.Transparent)
            .id('home-add-person').enabled(!this.busy).onClick(() => this.editPerson())
        }.width('100%')
      }
    }.width('100%').layoutWeight(1)
  }

  @Builder
  graphPage(mode: string, centerId: string) {
    Column({ space: 12 }) {
      if (mode === 'person') {
        Scroll() {
          Row({ space: 8 }) {
            ChoiceChip({ label: '全部关系', selected: this.graphRelationIds.length === 0, palette: this.colors, disabled: this.busy, onAction: () => { this.graphRelationIds = []; } })
            ForEach(this.data.relations, (item: NamedItem) => {
              ChoiceChip({ label: item.name, selected: this.graphRelationIds.includes(item.id), palette: this.colors, disabled: this.busy, controlId: 'person-graph-relation-' + item.id, onAction: () => { this.graphRelationIds = toggled(this.graphRelationIds, item.id); } })
            }, (item: NamedItem) => item.id)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      Scroll() {
        Row({ space: 8 }) {
          ChoiceChip({ label: '全部分支', selected: this.graphBranchIds.length === 0, palette: this.colors, disabled: this.busy, onAction: () => { this.graphBranchIds = []; } })
          ForEach(this.data.branches, (item: NamedItem) => {
            ChoiceChip({ label: item.name, selected: this.graphBranchIds.includes(item.id), palette: this.colors, disabled: this.busy, controlId: 'graph-branch-' + item.id, onAction: () => { this.graphBranchIds = toggled(this.graphBranchIds, item.id); } })
          }, (item: NamedItem) => item.id)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      NativeGraph({ payload: this.graphPayload(mode, centerId), theme: this.graphTheme(), paperColor: this.colors.paper, palette: this.colors,
        onPerson: (id: string) => this.graphPerson(id), onEvent: (id: string) => this.open('event', id),
        onBranch: (id: string) => { this.filterBranchIds = [id]; this.open('events'); } }).layoutWeight(1)
    }.width('100%').layoutWeight(1)
  }

  @Builder
  destination(name: string, param: Object) {
    NavDestination() {
      Column() {
        Column({ space: 8 }) {
          if (name !== 'aiHistory') {
            PageHeading({ title: routeTitle(name, this.tagKind), palette: this.colors, showBack: true,
              showAdd: name === 'people' || name === 'events', disabled: this.busy,
              onBackAction: () => this.goBack(), onAddAction: () => { if (name === 'people') { this.editPerson(); } else { this.editEvent(); } } })
          }
          this.feedback()
          if (name === 'people') { this.peopleList() }
          else if (name === 'person') { this.personDetail((param as RouteParam).id) }
          else if (name === 'personEditor') { this.personEditor() }
          else if (name === 'events') { this.eventsList() }
          else if (name === 'event') { this.eventDetail((param as RouteParam).id) }
          else if (name === 'eventEditor') { this.eventEditor() }
          else if (name === 'tags') { this.tagsPage() }
          else if (name === 'profileEditor') { this.profileEditor() }
          else if (name === 'appearance') { this.appearancePage() }
          else if (name === 'search') { this.searchPage() }
          else if (name === 'personGraph') { this.graphPage('person', (param as RouteParam).id) }
          else if (name === 'branchGraph') { this.graphPage('branch', '') }
          else if (name === 'image') {
            Column() {
              Image(this.fullscreenUri).width('100%').layoutWeight(1).objectFit(ImageFit.Contain)
                .scale({ x: this.imageScale, y: this.imageScale })
                .gesture(PinchGesture().onActionUpdate((event: GestureEvent) => {
                  this.imageScale = Math.min(5, Math.max(1, this.imageBaseScale * event.scale));
                }).onActionEnd(() => { this.imageBaseScale = this.imageScale; }))
              Text('双指缩放 · 点按恢复').fontSize(12).fontColor(this.colors.muted)
            }.layoutWeight(1).width('100%').clip(true).onClick(() => { this.imageScale = 1; this.imageBaseScale = 1; })
          }
          else if (name === 'ai') { this.aiPage() }
          else if (name === 'aiHistory') {
            AssistantHistoryPage({ chats: this.aiHistory.chats, activeId: this.aiHistory.activeId, disabled: this.aiSwitching,
              palette: this.colors, onBack: () => { this.goBack(); }, onNew: () => this.switchAssistantChat(''),
              onSelect: (id: string) => this.switchAssistantChat(id), onSearch: (query: string) => this.core().searchAssistantChats(query) })
          }
          else if (name === 'aiSettings') {
            AIServicePage({ previous: this.aiConfig, initialError: this.aiSettingsError, palette: this.colors,
              onSave: (url: string, key: string, model: string, remember: boolean) => this.saveAIConfig(url, key, model, remember),
              onSaved: () => { this.goBack(); } })
          }
          else if (name === 'backup') { this.backupPage() }
          else if (name === 'profile') { this.profilePage() }
          else if (name === 'desktopCard') {
            DesktopCardSettings({ data: this.data, initial: this.cardConfig, palette: this.colors,
              onSave: async (config: DesktopCardConfig): Promise<void> => {
                await DesktopCardStore.publish(this.getUIContext().getHostContext() as common.Context, this.data, config);
                this.cardConfig = config;
              } })
          }
        }.width('100%').height(editorDestination(name) ? '94%' : '100%')
          .padding({ top: 8, left: 20, right: 20, bottom: 12 }).backgroundColor(this.colors.paper)
          .borderRadius({ topLeft: editorDestination(name) ? 24 : 0, topRight: editorDestination(name) ? 24 : 0 })
          .clip(true)
      }.width('100%').height('100%').justifyContent(FlexAlign.End)
    }.hideTitleBar(true).mode(editorDestination(name) ? NavDestinationMode.DIALOG : NavDestinationMode.STANDARD)
      .backgroundColor(editorDestination(name) ? '#66131F18' : this.colors.paper)
      .onBackPressed(() => { this.goBack(); return true; })
  }

  build() {
    Navigation(this.paths) {
      Column({ space: 6 }) {
        PageHeading({ title: mainTitle(this.tab), palette: this.colors, showSearch: this.tab !== MainTab.Assistant,
          showAdd: this.tab === MainTab.People, showProfile: true,
          disabled: this.busy, onSearchAction: () => this.open('search'), onAddAction: () => this.editPerson(), onProfileAction: () => this.open('profile') })
        this.feedback()
        if (this.busy && !this.ready) { LoadingProgress().width(40).height(40).color(this.colors.primary); Blank() }
        else if (this.ready) {
          if (this.tab === MainTab.Graph) { this.homePage() }
          else if (this.tab === MainTab.Records) { this.eventsList() }
          else if (this.tab === MainTab.People) { this.peopleList() }
          else { this.aiPage() }
        } else { Blank() }
        if (this.tab !== MainTab.Assistant || !this.aiEditing) {
          Row({ space: 3 }) {
            MainTabButton({ label: '图谱', icon: $r('app.media.nav_graph'), selected: this.tab === MainTab.Graph, palette: this.colors,
              disabled: !this.ready || this.busy, controlId: 'tab-graph', onAction: () => this.selectTab(MainTab.Graph) }).layoutWeight(1)
            MainTabButton({ label: '记录', icon: $r('app.media.nav_records'), selected: this.tab === MainTab.Records, palette: this.colors,
              disabled: !this.ready || this.busy, controlId: 'tab-records', onAction: () => this.selectTab(MainTab.Records) }).layoutWeight(1)
            Button('＋', { type: ButtonType.Normal }).fontSize(28).width(50).height(50).padding(0).borderRadius(12)
              .backgroundColor(this.colors.primary).fontColor(this.colors.onPrimary).margin({ left: 6, right: 6 })
              .id('quick-add-event').accessibilityText('新建事件').enabled(this.ready && !this.busy).onClick(() => this.editEvent())
            MainTabButton({ label: '人物', icon: $r('app.media.nav_people'), selected: this.tab === MainTab.People, palette: this.colors,
              disabled: !this.ready || this.busy, controlId: 'tab-people', onAction: () => this.selectTab(MainTab.People) }).layoutWeight(1)
            MainTabButton({ label: '助手', icon: $r('app.media.nav_assistant'), selected: this.tab === MainTab.Assistant, palette: this.colors,
              disabled: !this.ready || this.busy, controlId: 'tab-assistant', onAction: () => this.selectTab(MainTab.Assistant) }).layoutWeight(1)
          }.width('100%').padding({ top: 6, bottom: 2 }).border({ width: { top: 1 }, color: this.colors.border })
        }
      }.width('100%').height('100%').padding({ top: 4, left: 20, right: 20, bottom: 8 }).backgroundColor(this.colors.paper)
    }.hideTitleBar(true).navDestination(this.destination).mode(NavigationMode.Stack).width('100%').height('100%')
  }
}

function toggled(items: string[], id: string): string[] { return items.includes(id) ? items.filter((item: string) => item !== id) : [...items, id]; }

function formatDate(timestamp: number): string {
  const date = new Date(timestamp);
  return date.getFullYear() + '-' + (date.getMonth() + 1).toString().padStart(2, '0') + '-' + date.getDate().toString().padStart(2, '0');
}

function readable(error: Error): string {
  const text = error.message || String(error);
  return text.replace(/^Error:\s*/, '');
}

function routeTitle(name: string, kind: string): string {
  if (name === 'desktopCard') { return '桌面关系卡片'; }
  if (name === 'people') { return '人物'; }
  if (name === 'person') { return '人物详情'; }
  if (name === 'personEditor') { return '记录人物'; }
  if (name === 'events') { return '事件'; }
  if (name === 'event') { return '生活记录'; }
  if (name === 'eventEditor') { return '记下一件事'; }
  if (name === 'profileEditor') { return '个人资料'; }
  if (name === 'appearance') { return '外观与主题'; }
  if (name === 'search') { return '搜索生活'; }
  if (name === 'personGraph') { return '人物生活图谱'; }
  if (name === 'branchGraph') { return '生活分支图谱'; }
  if (name === 'image') { return '图片'; }
  if (name === 'ai') { return 'AI 生活助手'; }
  if (name === 'aiHistory') { return '历史聊天'; }
  if (name === 'aiSettings') { return 'AI 服务'; }
  if (name === 'backup') { return '本地备份与恢复'; }
  if (name === 'profile') { return '我的'; }
  if (name === 'tags') { return kind === 'relations' ? '关系类型' : (kind === 'branches' ? '生活分支' : '情绪标签'); }
  return 'Life Graph';
}

