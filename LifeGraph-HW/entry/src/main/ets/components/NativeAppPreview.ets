import { NativeApp } from './NativeApp';
import { AppSnapshot, EventCard, NamedItem } from '../domain/Models';
import { Person } from '../domain/Person';

function fixture(): AppSnapshot {
  const data = new AppSnapshot(); data.profile.defaultPersonId = 'preview-me'; data.profile.displayName = '我';
  const self = new Person(); self.id = 'preview-me'; self.name = '我';
  const friend = new Person(); friend.id = 'preview-friend'; friend.name = '林晓'; friend.description = '大学时认识的朋友，喜欢一起散步、分享生活。';
  const family = new Person(); family.id = 'preview-family'; family.name = '妈妈'; family.description = '常常一起吃饭、聊最近的生活。';
  data.persons = [self, friend, family];
  const daily = new NamedItem(); daily.id = 'preview-daily'; daily.name = '日常';
  const study = new NamedItem(); study.id = 'preview-study'; study.name = '学习'; data.branches = [daily, study];
  const calm = new NamedItem(); calm.id = 'preview-calm'; calm.name = '平静'; data.emotions = [calm];
  const card = new EventCard(); card.event.id = 'preview-event'; card.event.title = '傍晚一起散步';
  card.event.content = '沿着河边走了很久，聊起那些值得记住的小事。'; card.event.occurredAt = new Date(2026, 9, 21).getTime();
  card.personIds = [self.id, friend.id]; card.branchIds = [daily.id]; card.emotionIds = [calm.id];
  const report = new EventCard(); report.event.id = 'preview-report'; report.event.title = '完成项目阶段汇报';
  report.event.content = '把这段时间的成果整理成了完整版本，也确认了下一阶段的方向。'; report.event.occurredAt = new Date(2026, 9, 25).getTime();
  report.personIds = [self.id, friend.id]; report.branchIds = [study.id];
  const dinner = new EventCard(); dinner.event.id = 'preview-dinner'; dinner.event.title = '和妈妈一起吃晚饭';
  dinner.event.content = '聊了最近的近况，也重新约好了下次见面的时间。'; dinner.event.occurredAt = new Date(2026, 8, 18).getTime();
  dinner.personIds = [self.id, family.id]; dinner.branchIds = [daily.id]; dinner.emotionIds = [calm.id];
  data.events = [card, report, dinner]; return data;
}

@Preview({ title: '我的页面（只读）' })
@Component
struct NativeProfilePreview {
  build() { NativeApp({ forcePreview: true, previewData: fixture(), previewRoute: 'profile' }) }
}

@Preview({ title: '新版人物列表（只读）' })
@Component
struct NativePeoplePreview {
  build() { NativeApp({ forcePreview: true, previewData: fixture(), previewRoute: 'people' }) }
}

@Preview({ title: '新版事件列表（只读）' })
@Component
struct NativeEventsPreview {
  build() { NativeApp({ forcePreview: true, previewData: fixture(), previewRoute: 'events' }) }
}

@Preview({ title: '新版首页（只读）' })
@Component
struct NativeHomePreview {
  build() { NativeApp({ forcePreview: true, previewData: fixture() }) }
}

@Preview({ title: '完整人物表单（只读）' })
@Component
struct NativePersonEditorPreview {
  build() { NativeApp({ forcePreview: true, previewData: fixture(), previewRoute: 'personEditor' }) }
}

@Preview({ title: '完整事件表单（只读）' })
@Component
struct NativeEventEditorPreview {
  build() { NativeApp({ forcePreview: true, previewData: fixture(), previewRoute: 'eventEditor' }) }
}
