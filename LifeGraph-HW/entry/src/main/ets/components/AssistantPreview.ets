import { AssistantBubble } from './AssistantBubble';
import { AssistantReference, AssistantTurn } from '../domain/Assistant';
import { Palette, ProfileConfig, paletteFor } from '../domain/Models';

function sample(): AssistantTurn {
  const turn = new AssistantTurn(); turn.id = 'preview-answer'; turn.createdAt = Date.now(); turn.readAt = Date.now();
  turn.text = '## 一段持续的联系\n从这些**演示记录**看，你们的共同经历既有日常相处，也有关键时刻的支持。\n\n| 观察角度 | 记录线索 |\n| --- | --- |\n| 持续性 | 多个阶段都有共同活动 |\n| 支持 | 遇到困难时留下过帮助的记录 |\n\n> 这是一种可能的解读，记录未覆盖的部分仍需要你判断。\n\n可点开[河边散步](lifegraph://event/preview-event)核对。';
  const ref = new AssistantReference(); ref.id = 'preview-event'; ref.title = '河边散步'; ref.occurredAt = new Date(2026, 9, 20).getTime();
  turn.references = [ref]; turn.contextNote = '界面示例，不读取或保存真实聊天，不代表真实 AI 分析。'; return turn;
}
function colors(dark: boolean): Palette {
  const profile = new ProfileConfig(); profile.appearance = dark ? 'dark' : 'light'; return paletteFor(profile, dark);
}

@Preview({ title: 'AI 回顾 · 浅色界面示例' })
@Component
struct AssistantLightPreview {
  build() {
    Scroll() { Column({ space: 12 }) { Text('界面示例 · 不保存数据').fontColor(colors(false).primary); AssistantBubble({ turn: sample(), palette: colors(false) }) }.padding(20).width('100%') }
      .width('100%').height('100%').backgroundColor(colors(false).paper)
  }
}

@Preview({ title: 'AI 回顾 · 深色界面示例' })
@Component
struct AssistantDarkPreview {
  build() {
    Scroll() { Column({ space: 12 }) { Text('界面示例 · 不保存数据').fontColor(colors(true).primary); AssistantBubble({ turn: sample(), palette: colors(true) }) }.padding(20).width('100%') }
      .width('100%').height('100%').backgroundColor(colors(true).paper)
  }
}
