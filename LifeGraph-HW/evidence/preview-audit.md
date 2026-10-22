# 普通页面预览误报成功的本机证据

检查日期：2026-10-21。此文件记录已观察到的路径和日志，不等同于修正后的交互验收。

- `entry/.preview/config/buildConfig.json` 的 `isPreview` 为 `true`，`previewPagePath` 指向本工程的 `entry/src/main/ets/pages/Index.ets`。
- DevEco `idea.log` 在 20:29:00、20:30:23、20:32:05 均记录当前页面为 `entry : /pages/Index`。
- 原始来源：`C:/Users/wangy/AppData/Local/Huawei/DevEcoStudio26.0/log/previewer.log`。

关键日志（按当时 rg 行号定位）：

| 原始行号 | 时间 | 接口与日志 |
|---|---|---|
| 28261 | 20:32:26.572 | The getRdbStore interface in the previewer is a mocked implementation and may behave differently than on a real device. |
| 28263 | 20:32:26.572 | The querySql interface in the previewer is a mocked implementation and may behave differently than on a real device. |
| 29628 | 20:32:31.231 | The insert interface in the previewer is a mocked implementation and may behave differently than on a real device. |
| 29629 | 20:32:31.231 | The querySql interface in the previewer is a mocked implementation and may behave differently than on a real device. |

原代码在显式 `PeoplePreview` 组件中传入 `previewOnly=true`，但 `Index` 只实例化默认 `previewOnly=false` 的页面，因此上述预览进入了数据库 Mock 并产生误导反馈。

推论边界：这些日志解释预览器内无法持久化的现象，也确认了应用预览保护不足；它们不说明真机 RDB 的行为。
