# 人物模块迁移试验记录

日期：2026-10-21。范围由实现者选择：人物列表、新建、编辑、搜索、软删除与本地存储。采用用户提供的 LifeGraph-HW 工程；不迁移用户旧数据。

## 已经验证的事情

- 本机存在 DevEco Studio 26.0.0.851，SDK 元数据为 HarmonyOS 26.0.0.105，内置 Hvigor 为 6.26.8。
- 保持原工程 `targetSdkVersion=26.0.0` 和 `compatibleSdkVersion=6.1.0(23)`，没有通过降低目标版本规避编译问题。
- 实际调用内置工具后，人物模块通过 ArkTS 编译、资源编译及 HAP 打包，输出 unsigned HAP。最终日志存入 `evidence/build.log`。
- 6 个主机逻辑测试通过，运行的是实际 `.ets` 业务服务，经 SDK 内置 TypeScript 解析器转换后执行，并非另写一份业务实现。测试边界为 Service + 内存 Repository。

## 实际遭遇的难点

### 1. TypeScript 代码不能无修改转成 ArkTS

第一轮成功进入 ArkTS 编译时，编译器拒绝两类写法：

- `constructor(private repository: PersonRepository, ...)`：`arkts-no-ctor-prop-decls`。需要显式声明成员，再在构造函数体中赋值。
- `catch (error) { throw error; }`：`arkts-limited-throw`。捕获值没有足够的类型保证，需要规范化为明确的 Error。
- 把页面拆成可复用组件后，`@Entry` 的根节点不能只写自定义组件，必须使用容器节点；已在入口增加 Column。该约束由实际编译器报错确认。

已修正并重新编译。这些属于迁移工作量，不能用“两个语言都类似 TypeScript”忽略。当前试验没有覆盖原项目的动态配置、泛型工具、联合类型和所有第三方库，因此不推断它们都可直接复用。

### 2. 分层设计可沿用，数据库实现需要替换

保留人物字段、Repository 抽象以及业务规则；将 Expo SQLite + Drizzle 改成 `@kit.ArkData` 的 relationalStore。具体需要重新处理：

- UIAbilityContext 到数据库创建的传递。
- 显式 ValuesBucket 字段映射及 ResultSet 空值读取。
- 查询游标的 finally 关闭。
- 毫秒时间戳和 `deleted_at IS NULL` 筛选。
- 更新／删除的影响行数检查。

这次只有一张人物表，写操作各自是一条 SQL，所以没有引入多表事务。不能据此声称原项目的人物关系、事件级联删除和账号隔离已经解决。本原型数据库连接由根页面持有，未扩展多页面、多窗口或账号切换的连接管理。

SDK 对部分原生数据库调用仍给出“Function may throw exceptions”静态警告。页面入口对初始化、保存、删除及刷新分别捕获错误并显示反馈；当前结果不是零警告构建。

### 3. React 的界面与状态绑定需要改写

本次没有继续使用 JSX、React Hooks、React Query、Zustand 或 Expo Router。重写为 ArkUI 组件、`@State` 和事件回调。业务层保持独立，界面重新读取 Repository 结果并整体替换数组，避免依赖原 React 的缓存失效机制。

保存成功但刷新失败时，必须先离开可重复提交的新建表单，再提示刷新失败；否则用户重试可能重复新增人物。本次已处理这一状态分界，但尚未在设备上注入数据库故障验证。

### 4. 本机构建工具链需要单独配置

- 默认 hvigorw 尝试安装 pnpm，当前运行环境无法解析 npm 包源域名，未能下载。
- 直接运行 Hvigor 时，必须正确找到 DevEco 现有 `@ohos/hvigor` 和 `@ohos/hvigor-ohos-plugin` 缓存依赖。
- 仅设 JAVA_HOME 不够：打包工具调用的是 PATH 上的 `java`。首次打包没有完成；将 DevEco 的 JBR/bin 放到本进程 PATH 首位、同时使用串行构建后，完整构建成功。由于同时调整了两项配置，未单独验证哪一项导致前次停滞。

`scripts/build-local.ps1` 固定上述环境，只读复用与内置插件版本匹配的 DevEco 缓存，并把新构建缓存写入本项目。没有修改系统级环境变量或 IDE 安装。

### 5. 预览与真实运行是两条验证路径

直接从命令行调用 PreviewBuild，缺少 IDE 注入的预览上下文，出现 `addOhmurlToHarAbility` 写入 undefined 和“Please restart previewer”错误。因此没有把这次调用当作视觉预览成功，也没有交付该调用为可用命令。

提供 `PeoplePreview.ets` 的三个 `@Preview` 组件，供 DevEco 正常预览流程使用。它们复用实际页面，只注入明确标注的示例数据；不访问数据库，也不模拟保存成功。需要人工打开验证并提供截图。

本次 `hdc list targets` 未返回设备 ID。工程的 `signingConfigs` 为空，打包跳过签名。没有完成安装启动、UI 操作、数据库实际读写、强制停止后重启或软键盘布局验证。

## 对完整迁移判断的修正

不迁移旧用户数据后，可以去掉“旧备份兼容／跨平台旧库恢复”的要求，明显减少数据迁移范围；新应用仍需完成自身数据库、文件及升级管理。

这次实证支持：独立的单表人物功能可以沿用业务语义，在现有鸿蒙工程内编译成 HAP。主要改写发生在 UI、数据适配和语言差异。它不构成图谱、录音、关系事务或 AI 全量迁移成本的证据。接下来有价值的验证是实际运行该模块，再单独试验 ArkWeb + D3 通信，或图片／录音持久化中的一项。

## 2026-10-21 用户反馈后的复查与修正

前文 6 项测试及“只提供显式预览组件”的结果是初次试验记录，以下为本轮更新，原代码的问题不能归咎于用户只使用了预览。

实际检查 DevEco 的 buildConfig 与日志确认：用户预览的是 `pages/Index`，`getRdbStore`、`insert`、`querySql` 均是预览器 Mock（摘要见 `evidence/preview-audit.md`）。原页面默认 `previewOnly=false`，没有覆盖普通页面预览；并且写 API resolve 后即显示成功，没有检查读回记录。这是代码缺口。

本轮已修正：

1. 实际 UIAbility 登记运行状态；显式组件预览以及未启动真实 Ability 的普通页面预览都只读，持续展示“界面预览 · 不保存数据”，不再调用生产写入路径。
2. 保存后核对重新读取的记录 ID、姓名、描述、更新时间；删除后核对活跃列表中已无记录，才展示成功。无法确认时退出新建表单，提示刷新核对，刷新不重复写入。
3. 从真正的 `@Entry Index` 转发系统返回事件，并在组件离开时清理回调。原先将 onBackPress 放在子组件中不足以保证返回键行为。

修正后的完整 unsigned HAP 构建已通过；10 项主机逻辑测试通过。新增测试直接覆盖预览门控、实际 RDB 适配器的“resolve 但无读回记录”替身、读回不一致、返回回调清理。此处没有把这些主机测试当成设备运行证据。

仍待验证：修正后的 DevEco 预览实际反馈、模拟器／真机 CRUD、重启持久化和返回键。未检测到真实设备数据丢失的确证，因此也不宣称真实数据库故障已修复。

完整方案见 `docs/superpowers/specs/2026-10-21-harmonyos-full-migration-design.md`（相对于工程根目录）。
