import { Person } from '../domain/Person';
import { PeoplePage } from './PeoplePage';

function previewPeople(): Person[] {
  const friend = new Person();
  friend.id = 'preview-friend';
  friend.name = '林晓';
  friend.description = '大学时认识的朋友，一起走过很多地方。';
  const colleague = new Person();
  colleague.id = 'preview-colleague';
  colleague.name = '周远';
  colleague.description = '喜欢摄影，也喜欢分享生活里的小发现。';
  return [friend, colleague];
}

// Visual previews only: fixtures never enter the real database.
@Preview({ title: '人物列表' })
@Component
struct PeopleListPreview {
  build() {
    PeoplePage({ previewOnly: true, previewPeople: previewPeople() })
  }
}

@Preview({ title: '新建人物' })
@Component
struct PeopleEditorPreview {
  build() {
    PeoplePage({ previewOnly: true, previewEditor: true })
  }
}

@Preview({ title: '首次启动' })
@Component
struct PeopleEmptyPreview {
  build() {
    PeoplePage({ previewOnly: true })
  }
}
