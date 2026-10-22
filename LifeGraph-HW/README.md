# Life Graph 鸿蒙版

基于用户提供的 LifeGraph-HW 工程，使用 ArkTS、ArkUI、ArkData 和原生媒体能力迁移原 Expo 应用。图谱复用原应用的离线 D3/SVG，通过 ArkWeb 显示。

当前是全量迁移的首轮实现，已构建并安装到 DevEco 模拟器，尚未完成全功能设备验收。旧用户数据不迁移；认证、会员、账号绑定和云同步等原未实现功能不在本轮补齐。原 Expo 工程保持只读。

## 当前能力

- 人物列表、搜索、详情、头像、关系类型和强度；隐藏并保留历史／彻底删除两种策略。
- 事件创建、编辑、删除，日期、地点、参与者、分支、情绪、颜色、图片和语音附件。
- 首页关系图、人物事件图、分支图，筛选、缩放、节点跳转和主题。
- 图片和音频选择、沙箱复制、录音、播放和图片缩放；取消编辑清理未引用附件。
- 个人资料、人数和事件数、四套主题、跟随系统／浅色／深色、自定义事件颜色。
- 鸿蒙版 ZIP 备份导出、预览和恢复；事务失败回滚、媒体校验和路径限制。
- 原有 AI 聊天接口与 11 个只读查询工具，超时／取消处理和基础 Markdown 展示。需配置实际可访问的后端地址，真实服务尚待联调。

具体完成度、替换决定、未适配部分及验收顺序见 [迁移进度](docs/migration-progress.md)。已发现问题见 [缺陷记录](docs/bugs.md)。

## 运行

1. 在 DevEco 打开本目录并完成 Sync。
2. 启动模拟器，在工具栏选择运行 entry。本机已经成功安装 unsigned 调试 HAP；这不代表真机或商店发行免签名。
3. 视觉预览入口为 entry/src/main/ets/components/NativeAppPreview.ets，提供新版人物列表、事件列表和首页。页面预览均只读，不将 Mock API 返回当作保存成功。
4. 真实应用包名暂为 com.lifegraph.harmony.spike，正式发布前再确定。数据库为 lifegraph.db；旧人物试验库不读取、不删除。

## 构建和测试

在本目录执行；默认 DevEco 路径为 F:/DevEco Studio。脚本复用 IDE 已有依赖，不修改系统环境或 IDE 安装。

```powershell
./scripts/build-local.ps1
./scripts/build-local.ps1 -Target ohosTest
& 'F:/DevEco Studio/tools/node/node.exe' scripts/test-person.cjs
& 'F:/DevEco Studio/tools/node/node.exe' --disable-warning=ExperimentalWarning scripts/test-core.cjs
& 'F:/DevEco Studio/tools/node/node.exe' scripts/test-extended.cjs
& 'F:/DevEco Studio/tools/node/node.exe' scripts/test-native-adapters.cjs
```

主应用产物：entry/build/default/outputs/default/entry-default-unsigned.hap。
测试模块产物：entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap。
构建日志：evidence/build-default.log、evidence/build-ohosTest.log。

2026-10-21：34 项主机测试通过；DevEco 模拟器独立原生 RDB 测试 1 项通过，验证建库、新增人物和事件、非法关系回滚、关闭重开读回。主应用强制停止再启动后，首页仍显示手测留下的三位人物及关系。设备重启、媒体完整流程、备份选择器和真实 AI 服务仍待验收。

主机 SQLite、ZIP 和桥接数据测试不等价于设备 UI 或性能测试。完整验收步骤见 docs/migration-progress.md。历史人物试验分析保留在 docs/migration-spike-findings.md；其中日期内的旧结果不是新版全量状态。

关系编辑专项：已修复强度文字不跟随滑条、选择人物后被其他控件的旧状态覆盖两项问题；实际模拟器的 8 个 UI 检查点通过，包括多行保存、强制停止重开、删行和重开编辑器。已存在的错误关系不自动猜测目标，需重新选择正确人物并保存。可运行 `python scripts/test-relations-ui.py` 复测；脚本会短暂操作模拟器界面，创建并清理一个唯一命名测试人物。

2026-10-22 按钮专项：修复事件参与者／生活分支／情绪不显示点选状态的问题，并调整同类筛选、外观、标题、主要操作和附件的状态更新。最新主程序构建及 34 项主机测试通过，分阶段累计 23 个不同设备检查点通过；整套设备脚本未完整通过。按用户要求停止设备检查，备份导出取消提示、实际媒体／录音和真实 AI 全流程仍待验证，详见 [按钮检查记录](docs/button-audit.md)。

2026-10-22 手测前对照排查：补齐分支多选、表单内分类管理、人物图谱关系筛选与空间概览；修正个人分支图范围、历史关系编辑、头像校验与清理、备份／录音故障处理、搜索和卡片刷新，并对齐预设色与资料校验。当前本地主机测试为 52 项；本轮新版没有安装或执行设备测试。原版依据、修改范围、验证边界及手测顺序见 [手测前排查记录](docs/pretest-review.md)。
