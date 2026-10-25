import { NativeApp } from './NativeApp';
import { AppSnapshot, EventCard } from '../domain/Models';
import { Person } from '../domain/Person';

function fixture(): AppSnapshot {
  const data = new AppSnapshot(); data.profile.defaultPersonId = 'preview-me'; data.profile.displayName = '我';
  const self = new Person(); self.id = 'preview-me'; self.name = '我';
  const friend = new Person(); friend.id = 'preview-friend'; friend.name = '林晓'; friend.description = '大学时认识的朋友，喜欢一起散步、分享生活。';
  data.persons = [self, friend];
  const card = new EventCard(); card.event.id = 'preview-event'; card.event.title = '傍晚一起散步';
  card.event.content = '沿着河边走了很久，聊起那些值得记住的小事。'; card.event.occurredAt = new Date(2026, 9, 21).getTime();
  card.personIds = [self.id, friend.id]; data.events = [card]; return data;
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
