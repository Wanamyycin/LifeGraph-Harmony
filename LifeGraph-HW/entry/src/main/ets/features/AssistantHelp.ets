export class HelpEntry {
  id: string;
  title: string;
  content: string;
  constructor(id: string, title: string, content: string) { this.id = id; this.title = title; this.content = content; }
}

export const ASSISTANT_HELP: HelpEntry[] = [
  new HelpEntry('people', '人物与关系', '首页点“人物”或“我的”页人物数量进入人物列表，点新建。填写姓名、描述、头像；添加关系后选择对象、类型与1～5强度，可添加多行。人物详情可编辑、打开生活图谱或删除。保留历史会隐藏人物并保留相关事件；彻底删除会移除人物及关联，只由此人参与的事件也会删除。“我”在个人资料中修改。'),
  new HelpEntry('events', '事件与附件', '首页“＋记录”或底部“＋”新建事件。标题、日期和至少一名参与者必填；分支、情绪、地点、正文可选。点选标签可再次取消，“未设置”清空分支；表单中的管理入口可新增、改名、删除分类，返回保留草稿。可导入图片或音频、录音、设图片封面、移除附件。录音先停止再保存。取消表单不会删除原来已保存的附件。事件列表分支支持多选，任意命中即可显示。'),
  new HelpEntry('search', '查找与图谱', '首页右上角搜索可查人物或事件；事件列表也能搜索及筛选。人物详情可打开人物生活图谱，分别筛选关系和生活分支；我的页可打开生活分支图，它只展示“我”参与的事件。图谱可拖动、缩放、点人物或事件打开记录。'),
  new HelpEntry('appearance', '外观与个人资料', '我的页进入个人资料，修改称呼（最多24字）、个人见解（最多200字）、头像和生日。外观与主题提供森林、海洋、日落、极简，以及跟随系统、浅色、深色；设置保存在本机。自定义事件色使用六位十六进制颜色，例如 #5B8C5A。'),
  new HelpEntry('backup', '备份与恢复', '我的页进入本地备份与恢复，查看空间统计并导出 ZIP。备份包含本机人物、关系、事件、媒体、个人设置和聊天记录。恢复只接受此鸿蒙版备份，选择后先确认时间和数量；恢复会替换当前记录，建议先导出当前备份。旧版 Expo 备份和云同步不支持。'),
  new HelpEntry('ai', 'AI 助手与隐私', '可查找记录、总结经历、分析关系或解释软件用法。关系强度判断只给建议，人物和事件由你自己修改。服务设置弹窗填写 OpenAI 兼容接口 URL、API Key 和模型名称，模型需支持 Chat Completions 工具调用；支持根地址、/v1 地址或完整 /chat/completions 地址。问题、近期对话和必要的文字记录将直接发送到你填写的服务，不发送照片、音频或整个数据库。密钥可保存在本机安全存储，也可取消勾选仅本次运行使用；AI 服务配置不进入聊天和导出备份，换设备需重新填写。使用说明可在本机直接阅读。查询记录可点开核对，聊天保存本机、可清空，并随本机备份保存。未实现登录、会员、账号绑定、云同步、通知投递和自动更新。')
];

export function appHelp(query: string): HelpEntry[] {
  const text = query.trim().toLocaleLowerCase();
  const exact = ASSISTANT_HELP.filter((entry: HelpEntry) => entry.id === text || entry.title.includes(text) || entry.content.includes(text));
  return text.length === 0 || exact.length === 0 ? ASSISTANT_HELP : exact;
}

export function localHelpText(): string {
  return '# 使用 Life Graph\n\n' + ASSISTANT_HELP.map((entry: HelpEntry) => '## ' + entry.title + '\n' + entry.content).join('\n\n');
}
