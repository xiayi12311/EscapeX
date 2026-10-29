# TheHeadTeacher 交接记录

> 2026-10-23 最新方案：用户已确认将玩家端点改为碰撞包围盒单点（Center.Z + Extent.Z × 0.75），移除玩家骨架租用及释放调用；旧目标插槽/骨架参数不再使用。怪物头部插槽和锥体候选规则保留。离线 24/24 通过，最新 PIE 验证结果见 Tests/BoundsSight/验证记录.md。下文旧骨架方案仅作历史记录。

> 2026-10-23 后续诊断更正：DS 的 Mesh 父子关系实际存在，但 Mesh 与 MeshContainer 开启了绝对位置；A/B 已证明该开关会让补模型后的头部插槽落到原点。另有 bNoSkeletonUpdate=true。本文第 4.5 节“脱离挂接”及其修复解释须结合最新排查记录阅读，不能据此认定重新挂接已解决问题。详见 [DS玩家Mesh_原因排查_2026-10-23.md](DS玩家Mesh_原因排查_2026-10-23.md)。

> 第二轮补充：基础 BP_PlayerPawn 的 GetNonDedicatedComponents 名单包含 CharacterMesh0；日志在 Possess 后执行 DeactivateNonDedicatedComponents。两层绝对位置和骨骼禁止更新标志在此窗口变为 true。DS 类默认对象的动画类则早已为空，属于更早阶段的差异。纯 Lua 同名覆盖没有拦截原生接口，不构成有效绕过实验；具体 C++ 赋值函数尚未取证。第二轮 PIE 与临时脚本均已清理恢复。

整理日期：2026-10-23（当日续作后重写）。状态：导航持久化、锥体朝向、追逐流畅度、抓取判定、遮挡检测均已修复并验证；玩家视线端点已按用户决定改为**碰撞包围盒单点**（见 4.7），站/蹲姿态跟随已受控验收通过。实现整体尚未验收完成，未完成项见第 7 节。PIE 会话 `dkcx30fnv00sk2` 于 17:35 启动，验收后按需停止。

---

## 1. 用户约束与阅读入口

- 依据 `E:/HPYJ/EscapeX/Docs/TheHeadTeacher_怪物设计.md` 实现。
- 用户明确要求：**不要自建状态机**，有需要使用自定义行为树。现有实现由行为树调度四个任务，没有另建状态机。
- 用户允许自行配置默认值，要求做成可调整参数。默认值：视野长度 1000cm、完整开角 60°、抓取胶囊表面间距 30cm、巡逻速度 150、追逐速度 500、占位伤害 300。
- 人脸识别已由用户完成，DS 实测已打通，不再是阻塞。
- 后续开发先查本地知识库：`knowledge/gp-docs/README.md` 与 `AGENTS.md`；官方快照日期 2026-10-22。跨工程结论在 `knowledge/recipes/`（本轮的 4 条配方见第 10 节）。
- 旧《实现记录》《怪物设计》的阶段描述可能滞后，**以本交接记录为准**。

## 2. 工程、分支与文件位置

- 工作副本：`E:/HPYJ/EscapeX`（脚本与文档的源；编辑器**不会**自动加载这里的 Script）。
- 编辑器实际工程：`E:/WeGameApps/rail_apps/OasisEraEditor(2001776)/ShadowTrackerExtra/UGCProjects/EscapeX`，挂载点 `/EscapeX`。
- Git 主仓库：`https://github.com/xiayi12311/EscapeX`
  - `main` = `c1b2cab` 新建项目。
  - `feature/headteacher-ai` = `caa82d3`，本轮班主任 AI 的第一个提交（19 个文件）。
  - **当前工作区在 `feature/searchable-desk`**（从 `caa82d3` 切出，另一个并行功能"可搜索桌子"正在进行）。工作区里混有两部分未提交内容：
    - 班主任 AI 后续改动：`Script/AI/HeadTeacher/HTCommon.lua`、`BTT_*.lua`、`UGCmap.umap`（测试掩体）、`Tests/`。
    - SearchableDesk 功能：`Asset/Blueprint/Prefabs/Interactables/`、`Asset/Sequences/`、`Asset/UI/`、`Script/Gameplay/Desk/`、`Script/Blueprint/UGCPlayerController.lua`、`Docs/SearchableDesk_*.md`、`Tests/desk_*` 等。
  - **提交时务必把两个功能分开**，不要混进一个 commit，也不要覆盖或撤销他人的未提交文件。
  - 本机提交身份（全局配置）：`GZYV <guangzhiyingv@gmail.com>`。

已部署脚本（工作副本与实际工程逐字节一致）：

| 文件（相对工作副本） | 说明 |
| --- | --- |
| `Script/AI/HeadTeacher/HTCommon.lua` | 共享逻辑：锥体、射线、移动、抓取判定、诊断埋点 |
| `Script/AI/HeadTeacher/BTT_HTPatrol.lua` | 巡逻 + 扫描 + 锁定 |
| `Script/AI/HeadTeacher/BTT_HTChase.lua` | 追逐（判定帧记录抓取距离） |
| `Script/AI/HeadTeacher/BTT_HTCatch.lua` | 抓取结算（复用判定距离） |
| `Script/AI/HeadTeacher/BTT_HTReturn.lua` | 返回最近路点 |
| `Script/Blueprint/Prefabs/Monsters/TheHeadTeacher.lua` | 怪物表现/伤害入口/EndPlay 释放骨架 |
| `Script/Blueprint/UGCGameMode.lua` | 导航启动构建 + TestAutoRevive（+ 并行功能的 Desk 钩子） |

部署注意：必须保留引擎生成区（`---@class`、`---@field` 参数注解、`--Edit Below--` 标记）。工作副本曾丢失这些内容（TheHeadTeacher.lua 从 24 条注解降到 2 条、UGCGameMode.lua 丢失标记），已按部署版重新合并；不要再用旧工作副本整目录覆盖实际工程。

## 3. 当前实现

资产目录 `/EscapeX/Asset/AI/HeadTeacher/`：

- `BB_HeadTeacher`：`LockedTarget`（Actor）、`CatchReady`（Bool）、`ChaseSequenceId` / `ProcessedSequenceId`（Int）。
- `BT_HeadTeacher`：可编辑源图；`BT_HeadTeacher_RuntimeData`：DS 实际加载的运行树（源图与运行树必须区分）。
- `BTT_HTPatrol`、`BTT_HTChase`、`BTT_HTCatch`、`BTT_HTReturn`：父类 `BTTask_LuaBase`，绑定对应 Lua。

行为树：`Patrol → Chase → Catch → Return → 根循环`。

- **Patrol**：每 0.1s 扫描锥体重叠候选，去重后按距离与 PlayerKey 稳定选择，通过插槽射线后锁定唯一目标。
- **Chase**：保留锁定目标，不因距离/失去视线/寻路失败而换人；每 0.5s 重试移动。目标失效则清理并回归。
- **Catch**：先记录轮次已处理再调用处理函数；每轮最多一次，异常也清理。抓取条件 = 胶囊表面间距 + 无遮挡射线。
- **Return**：开始时选最近路线点（等距按路线顺序），抵达前不重新检测、不换点、不瞬移兜底，失败持续重试。
- 运行数据在 `HTRuntime`；任务中止停止移动；已有黑板目标时树重启不会再次扫描换人。
- 锥体使用现有 `RedLightMesh`（四块凸碰撞）同时做可视范围与重叠查询，绑定 `headSocket`；未实现贴墙裁剪。
- 射线：怪物 Mesh 插槽 → 玩家 Mesh 插槽，`ECC_Visibility = 3`，忽略怪物自身；插槽缺失不判定可见。
- 抓到处理走 `UGCGameSystem.ApplyDamage`，默认 300；保留原 `BPDie`。

路线点：预制体 `Asset/Blueprint/Prefabs/AI/BP_HTWaypoint`（拖入地图即为一个点；`RouteName` 分组、`RouteIndex` 顺序，同序号为一档、档内随机选点、末档回到首档循环，0 未设时按对象名排序；`WaitTime` 为到达后的停留秒数，0=不停留，停留期间朝该点箭头方向（点位 Actor 的 Yaw）；Marker 为 Arrow，游戏内隐藏、无碰撞）。收集：`HTCommon.routes` 每 `HTRouteRefreshInterval`（默认 2s）重建——按类扫描 `/EscapeX/Asset/Blueprint/Prefabs/AI/BP_HTWaypoint.BP_HTWaypoint_C`，并兼容旧地图手打标签 Actor（`HT_Route` / `HT_Route_NNN`）。分组开关：可选 `BP_HTRouteGroup`（`GroupName`/`RouteTag`/`bEnabled`）；有控制 Actor 的组只在该控制 `RouteTag` 匹配怪物 `HTRouteTag` 且 `bEnabled=true` 时巡逻，无控制 Actor 的组按旧规则（组名 == `HTRouteTag`）。因此运行中拖放/删除点位、勾选分组开关，最迟 2s 生效。旧坐标记录：(19210,27840,100)、(19210,29040,100)、(20410,29040,100)。

场景（2026-10-29 在 `map init` 新图上重建）：`HT_Navigation`（NavMeshBoundsVolume，中心 15685/30670/1000，半范围 3800/3800/2000，覆盖玩法区：书桌/监狱柱/刷怪点/巡逻点）、`HT_AIWorld`（AIWorldVolume，中心 16555/17415/800，半范围 19500/20000/1800，覆盖全图，一图一个）、`UAERecastNavMesh-Mannequin`（随导航体积自动生成：`RuntimeGeneration=2` 动态、`bUGCDynNavData=true`、`bForceRebuildOnLoad=false`）。GameMode 含 `ESS_Navigation=33`、`ESS_MonsterCrowdMove=50`、`GMDataSource_Navigation`、`HTBuildNavigationOnStart=true`（开局 `AsyncBuildNavmesh(self,"Mannequin")`）。关卡已保存；未做编辑器「构建」烘焙，沿用运行时异步构建方案。
环境雾（2026-10-29）：`HT_Fog`（ExponentialHeightFog，位于 15685/30670/1000）：`FogDensity=0.03`、`FogHeightFalloff=0.2`、`StartDistance=1500`、`FogMaxOpacity=0.9`，用于压缩玩家可视距离（约 5–8 十米外强衰减，近处不受影响）；参数收紧/放宽改密度即可，已随关卡保存。

**测试掩体**：`HT_TestCover`（StaticMeshActor + `/Engine/BasicShapes/Cube`，缩放 (1,10,4)，中心 (20600,28740,300)），即 100×1000×400cm 南北向墙，夹在巡逻路线与玩家出生点 (20830,28740) 之间。

## 4. 2026-10-23 完成项

### 4.1 导航持久化 ✅

- `UAERecastNavMesh-Mannequin`：`RuntimeGeneration` 0→**2（Dynamic）**，`bUGCDynNavData` false→**true**，`bForceRebuildOnLoad` 保持 false，关卡已保存。
- 该 actor 原本 `LoadInDS/LoadInPIE=True`、`LoadInClient/LoadInEditor=False`；问题不在加载开关，而是 Static(0) 且没有导出文件（`NewNavDataPath`、`navMeshFileName` 为空，`Navmesh` 目录为空，`bUGCNavData` 只读为 false）。
- GameMode 蓝图新增 bool `HTBuildNavigationOnStart=true`（编译保存）；`UGCGameMode.lua` 在 `ReceiveBeginPlay` 调 `UGCNavigationSystem.AsyncBuildNavmesh(self,"Mannequin")`（接口按 `knowledge/gp-docs/raw/api/ab7b7e50332b.json` 核对）。
- 实测：多次 PIE 开局均打印 `[HeadTeacher] Initial dynamic navigation build requested`，无需手工改 DS 即可巡逻。
- 非阻塞后续：研究编辑器「构建」导出 .navmesh 的静态方案。

### 4.2 锥体朝向 ✅

- 蓝图 CDO 与场景实例 `HTConeRoll` 由 +90 改为 **-90**（Pitch=0、Yaw=-171.49657 不变），蓝图与关卡已保存。
- 依据实测 headSocket 世界旋转（roll=-90、pitch=81.4965、yaw=0）与其基向量推导：旧配置世界锥轴 = (+1,0,0)（开口朝后，与 DS 实测一致）；翻转后 = (-1,0,0)（开口沿 forward）。
- 运行时实测：`OPEN_DIR=(-0.0012,1.0000,0.0000)`、`FWD=(-0.0012,1.0000,0.0000)`、**DOT=1.0000**，|锥体中心-头部插槽|=500.0cm。

### 4.3 追逐流畅度 ✅

- 现象：玩家跑动时怪物"走一段停一下"，贴近后先停顿再抓取。
- 根因：`UGCGenericCharacterSystem.MoveTo` 是"到点停车"的指令；目标在两次重发之间移动后，怪物走到旧目标点就停下，等下一次重发才继续（0.5s 周期下单次短但频繁，2s 周期下长停顿）。
- 修复（`HTCommon.moveTick`）：缓存上次目标点 `task.Goal`；**已停下且离当前目标 >10cm** 立刻重发；**距旧目标 ≤250cm 且目标已移开 >50cm** 提前切换路径。巡逻/返回为固定目标，提前条件恒假，行为不变。
- 实测：间隔强制 2s、目标持续移动时，追逐 141 采样静止 9（约 6%，前 14s 连续 500）；正常 0.5s 间隔 35 采样静止 2（均在抓取结束瞬间）。
- 已实测排除 `CrowdAgent:MoveToActor`：单独调用后怪物 3 秒完全不动；`MoveToLoc` 能驱动但上限 200cm/s 且通用速度查询读不到。

### 4.4 抓取判定：帧间复查竞态 ✅（A 方案）

- 现象：追到近处偶尔不结算伤害就返回。
- 根因：Chase 在本帧测距并置 `CatchReady`，Catch 在下一帧用**新测距**复查 `≤30cm`；目标以 700–1100cm/s 移动时一帧（33ms）拉开 23–36cm，越过阈值。成功样本都是目标静止（两次测量位置完全相同）。
- 判定频率：`ReceiveTickAI` 任务活动期间**每帧调用**（wiki 20265），不是可配定时器；实测间隔 33–34ms（PIE DS≈30fps），60fps 约 16ms。调频率不能根治（18cm/帧仍可能越界）。
- 修复：Chase 记录**判定帧距离**与轮次（`HTRuntime.catchGap/catchSeq`）；Catch 复用该值，只重查 `alive`/`visible`；加 `HTCatchSanity=200cm` 瞬移兜底（超出记 `TELEPORT`）。结算/Return 清空。
- 验证：离线新增两条（20→50 仍抓、20→332 拒绝），**21/21 通过**；PIE 自然追逐 seq 1–9 全部 `catch_hit`。**驱动制造竞态的端到端复现未做成**（客户端未注册），用例已按实测数值覆盖。

### 4.5 遮挡失效：DS 玩家网格脱离角色 ✅根因（该修复已被 4.7 的包围盒方案取代）

- 现象：玩家躲在石头/墙后仍被看见并锁定。
- 定位：`vis_clear src=(19805,29017,262) dst=(-2,0,160) mesh=(0,0,0)`——玩家 `Mesh` 组件在 DS 上悬空在世界原点，头部插槽随之落在原点附近；射线射向地图原点，任何掩体都挡不住。
- 根因：DS 玩家 Pawn 的 `Mesh` 未挂在角色层级里，且已有 `SkeletalMesh`，原"租用骨架"分支（条件 `not mesh.SkeletalMesh`）不会执行，挂接代码从未运行。
- 修复（**检测逻辑不变**）：在 `M.visible` 读取插槽前把玩家 `Mesh` 挂到 `MeshContainer` 或 `CapsuleComponent`，相对位置设为胶囊底部（`Z=-halfHeight`），每次扫描同步；目标点仍是**头部插槽**（不是胶囊顶部）。插槽仍离角色 >300cm 时打印 `sight-socket` 告警（只告警）。
- 已确认的部分：端点纠正到玩家位置后 `vis_blocked ... dst=(20830,28740,278)`，怪物不锁定——**遮挡链路本身是通的**。
- 未确认：最终"插槽跟随"版本尚无端到端样本；该 PIE 客户端一直未注册到 Lua 控制台，且玩家在墙后时巡逻锥角扫不到出生点。
- 测试注意：编辑器世界里运行时新建的 StaticMeshActor **没有物理体**（编辑器内射线打不中）；保存后 PIE 从磁盘加载的实例才有碰撞。

### 4.6 测试环境与诊断埋点

- 测试掩体 `HT_TestCover`（见第 3 节），用于墙后/暴露的对照。
- 临时埋点：`HTCommon.M.TRACE = true`（顶部开关），前缀 `[HT_TRACE]`。事件：`patrol_enter/lock/abort`、`chase_enter/tick/exit/abort`（原因码 `SEQ_MISMATCH`/`TARGET_LOST`/`CATCH_READY`）、`catch_hit/skip`（原因码 `READY`/`ALIVE_*`/`PROCESSED`/`GAP`/`TELEPORT`/`VISIBLE`）、`vis_clear/vis_blocked`（含射线两端坐标与命中对象）、`lease_attach`。
- 埋点**目前开着**，合并/交付前改为 `false`。

### 4.7 玩家视线端点改为包围盒单点 ✅（用户确认的最终方案）

- 用户决定：不用玩家插槽，也不用胶囊顶部代替；直接取玩家**碰撞包围盒**的一个点作为视线终点。
- 实现（`HTCommon.sightPoint`）：`GetActorBounds(true, Center, Extent)`，`Z = Center.Z + Extent.Z × HTTargetBoundsHeightRatio`（默认 0.75，允许 0–1；仅存在于 Lua Defaults，**尚未**加蓝图编辑器变量）。包围盒无效时跳过并诊断，不换别的端点。
- 同时移除：玩家骨架加载/动画更新/挂接、`ServerRigs` 租用与释放、`releaseUnusedRigs` 调用、插槽跟随代码。源端仍是怪物 `headSocket`；锥体重叠候选、锁定、抓取流程不变。
- 射线改为忽略 `{怪物, 玩家}`，只用"是否命中其他障碍"判断可见；**不再读取 FHitResult 的 Actor/Component/Owner/名称**——旧 `GetObjectName(hit.Actor)` 在本版本会触发 FName/IsValidIndex 引擎断言，已实测崩溃一次。
- 站/蹲验收（会话 `dkcx30fnv00sk2`，17:42:46–17:43:30，用户手动切换 12 次，DS 每 1.2s 采样）：
  - 站立：capsuleHalfHeight=88 → centerZ=190.15、extentZ=88、pointZ=**256.15**；
  - 蹲下：capsuleHalfHeight=60 → centerZ=162.15、extentZ=60、pointZ=**207.15**；
  - 包围盒底边恒为 102.15，端点随姿态下移 49cm；同窗口 AI 射线 `dst z` 就在 207/256 之间逐帧切换。
  - **`bIsCrouched` 恒为 false，不能作为姿态判据**；姿态只能从胶囊半高/包围盒读。
- 遮挡：玩家在 `HT_TestCover` 后，蹲站全程 `vis_blocked`、无锁定；`visible=true` 的暴露样本来自 17:26:49 同一方案的早前采样。
- 代价与边界：端点是固定比例点，不跟随上身/头部骨骼动画（低头、探头不改变端点）。这是用户确认的可接受近似。

## 5. 验证证据

- 会话 `dkcx30fnuzdj47`、`dkcx30fnuzemqk`：自动建图 → Patrol → Chase → Catch（`appliedDamage=300.0` 单次）→ Return → Patrol，全程无手工 DS 修改。
- 会话 `dkcx30fnuzn8gp`：抓取竞态 4 次失败样本（gap 17.6→53.7 等）。
- 会话 `dkcx30fnuzp4qm`：A 方案后自然追逐 seq 1–9 全 `catch_hit`。
- 会话 `dkcx30fnuzstge`：遮挡根因证据（`dst=(-2,0,160)`、`mesh=(0,0,0)`）；端点纠正后 `vis_blocked`。
- 会话 `dkcx30fnuzzjgz`：包围盒方案首轮，暴露旧 `GetObjectName(hit.Actor)` 断言崩溃（已修复）。
- 会话 `dkcx30fnuzzwjo`：包围盒方案墙后 `visible=false`、墙前 `visible=true`，玩家 `mesh=nil`，端点 Z=207.15。
- 会话 `dkcx30fnv00sk2`：站/蹲受控切换 12 次，端点 256.15↔207.15；同窗口全程 `vis_blocked`。详见 `Tests/BoundsSight/验证记录.md` 与 `native-evidence.log`。
- 日志目录：`E:/WeGameApps/rail_apps/OasisEraEditor(2001776)/ShadowTrackerExtra/Saved/Logs/EscapeX/DSlog/FullLog/`。

## 6. 离线测试

`EscapeX/Tests/run_headteacher_tests.py` + `headteacher_tasks_test.lua`（Lupa 2.8 / Lua 5.1），当前 **24/24 通过**：

```powershell
& 'C:\Users\27781\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' E:\HPYJ\EscapeX\Tests\run_headteacher_tests.py
```

覆盖：路线端点/排序、三维胶囊距离、插槽缺失、遮挡结果、候选去重、锁定与重试、每轮伤害去重/异常、固定最近回归点、Abort、移动重寻路（停下/提前）、抓取判定复用与瞬移拒绝。均为 mock，不证明原生碰撞、导航、动画或骨架恢复。

## 7. 未完成 / 验收边界

- 遮挡：墙后不发现、暴露即发现、站/蹲跟随已验收；**未做**：比遮挡物更低的矮掩体（蹲下端点 207 但墙高 400，未覆盖顶边比蹲姿更低的情形）。
- 正后方不触发、锥体边缘角度与距离边界。
- 多人同时可见的最近优先与稳定选择。
- 完整 OneWayLoop 往返（含两端折返）长时间运行。
- 玩家挡路不阻塞怪物。
- `HTTargetBoundsHeightRatio` 目前只能改 Lua Defaults，若要给策划调，需要加蓝图变量。
- 抓取竞态的驱动复现（判定帧近、复查帧远）。
- 旧《实现记录》与设计文档阶段状态同步。

## 8. 继续工作的步骤

1. 确认编辑器打开的是 EscapeX（`/EscapeX/UGCmap`）；核对工作副本与实际工程脚本一致（逐文件 SHA256）。
2. 端到端复测（第 7 节剩余项）：
   - 已验收：墙后持续 `vis_blocked` 不锁定；暴露 `vis_clear` 锁定；蹲下端点随包围盒下降（207 ↔ 256）。
   - 未覆盖：比蹲姿更低的矮掩体；正后方；锥体边缘角度/距离；多人优先级。
   - 复测时先确认 PIE 客户端已注册（`doluastring` 能打日志），否则采样无输出。
3. 抓取竞态：用传送驱动把目标保持在判定边界附近复现，确认不再出现 `catch_skip reason=GAP`。
4. 关闭埋点（`HTCommon.lua` 顶部 `M.TRACE=false`）再提交/合并。
5. **提交注意**：当前工作区在 `feature/searchable-desk`，且混有 SearchableDesk 功能；提交班主任改动时只 add 本功能的文件，不要带上 Desk 的资产/脚本；分支与 PR 按团队规范。

## 9. 编辑器与接口经验（避免重复踩坑）

1. 行为树源图与运行树必须区分；源图改动后要重新生成运行树（运行副本的根节点 Outer 必须是 BehaviorTree 的 `BTComposite_Sequence`，修正 Children/ParentNode/TreeAsset，清空 BTGraph/LastEditedDocuments）。`bt_add_node` 后 RootNode 可能为 nil，关闭重开 BT 编辑器可生成结构；根节点 BlackboardAsset 必须正确，否则回到 `BB_PlayerAutoCombatBase`。
2. `duplicate_asset` 源参数传完整对象路径（`/EscapeX/.../BT_HeadTeacher.BT_HeadTeacher`），省略后缀会得到 544 字节空包。
3. 蓝图字符串变量类型用 `string`（不是 `str`）；不要执行 `bp.NewVariables=bp.NewVariables`（列表别名清空问题）；新增变量后必须 `compile_blueprint` 并保存 CDO。
4. Lua 读 `BehaviorTreePath` 软引用可能为 nil，不能据此判断未绑定；查黑板与任务运行日志。
5. `doluastring` 单向派发：返回 `{}` 只代表已派发，结果必须看 DS 日志；客户端注册到 Lua 控制台约需 3 分钟，报 `No PIE client window is registered` 先等再试。
6. `ue.get_asset(path)` 返回 FAssetData/Package，不是资产对象；UBlueprint 用 `ue.load_object(ue.find_class('Blueprint'), path)`，生成类用 `ue.load_class('<asset>.<Class>_C')`，`get_cdo()` 只接受 UClass。
7. Python 侧 FVector 分量为 `.x/.y/.z`（构造用 `ue.FVector(x,y,z)`），Lua 侧为 `.X/.Y/.Z`；`blueprint_set_variable_default_value` 不存在，改用 add → compile → CDO `set_property` → `save_package`。
8. `ue_py` 抛异常会回滚事务，但之前执行的 `save_package()`/`editor_command_save_current_level()` 可能已落盘；出错必须回读确认，不能假设已回滚。
9. 资产改动（蓝图变量、地图、行为树）必须重启 PIE 才生效；**Lua 改动也要在部署落盘之后启动 PIE**——曾出现文件落盘比 PIE 启动晚 3 秒，导致当次会话加载旧脚本、诊断行不出现。
10. 运行时新建的 StaticMeshActor 在编辑器世界没有物理体；保存关卡后由 PIE 从磁盘加载才有碰撞。用编辑器内射线验证会得到假阴性。
11. DS 上玩家 `Mesh` 可能悬空在世界原点（本工程实测），射线/插槽会因此失效；先看插槽世界坐标是否跟随角色，再查检测逻辑。
12. DS Lua 环境有 `UGCGameSystem.GameMode`（世界上下文）、`UGCActorComponentUtility.GetAllActorsOfClass`、`UGCGameSystem.GetAllPlayerPawn`；`World` 全局只是 UWorld 类表，不能当实例用。`UGCActorComponentUtility.SetActorLocation` 对 Pawn 无效，要用 `K2_SetActorLocation(..., bTeleport=true)`。
13. `UGCGenericCharacterSystem.GetCurrentVelocity` 看不到群体移动（`CrowdAgent:MoveToLoc`）驱动的速度；`CrowdAgent:MoveToActor` 在本工程实测无效。
14. 行为树任务 tick 是每帧，不可配置更细；跨任务/跨帧的判据要做一致性处理（见配方 catch-recheck-frame-race）。
15. 玩家姿态**不要读 `bIsCrouched`**：本工程 DS 上站/蹲全程都是 false，但胶囊半高与 `GetActorBounds` 会真实变化（88↔60）。姿态判据只取胶囊半高或包围盒。
16. PIE 客户端没拿到焦点时，键盘输入不会进游戏；采样前先让用户点一下游戏窗口，否则会得到一长串“姿态没变”的假阴性。

## 10. 备份与相关文档

- 备份：`Backups/HeadTeacher_BeforeResume_2026-10-23`（4 份脚本、怪物蓝图、GameMode、关卡、行为树资产）；更早的 `Backups/HeadTeacher_BeforeImplementation`。
- 跨工程配方（`knowledge/recipes/`）：
  - `chase-moveto-stutter.md`（MoveTo 到点停车与重寻路）
  - `catch-recheck-frame-race.md`（抓取判定跨帧竞态）
  - `ds-player-mesh-detached.md`（DS 玩家网格脱离、射线终点落到原点）
  - `pie-verify-timing.md`（PIE 验证时序坑）
  - `revive-in-place.md`（TestAutoRevive 使用的复活接口链）
- 本文件同步副本：工程内 `Docs/TheHeadTeacher_交接记录.md`。

## 11. 2026-10-29 巡逻点资产化与分组实时开关（未实测）

- 新资产（编辑器 Python 创建，配方见 `knowledge/recipes/blueprint-asset-scripting-limits.md`）：
  - `Asset/Blueprint/Prefabs/AI/BP_HTWaypoint`：`RouteName`（string，默认 `HT_Route`）、`RouteIndex`（int，默认 0）；CDO 标签 `HT_Route`；Marker 为 ArrowComponent（游戏内默认隐藏、无碰撞），地图里可见一个箭头。
  - `Asset/Blueprint/Prefabs/AI/BP_HTRouteGroup`：`GroupName`、`RouteTag`（均 string，默认 `HT_Route`）、`bEnabled`（bool，默认 true）；不带 `HT_Route` 标签，避免被当成路点收集。
  - 两个 Lua 绑定 stub 由 `bp_lua_find_or_create` 生成于 `Script/Blueprint/Prefabs/AI/`，无外部依赖。
  - 实例参数编辑：选中地图上的实例，在右侧细节面板的“巡逻点”（`RouteIndex`/`RouteName`/`WaitTime`）或“巡逻分组”（`GroupName`/`RouteTag`/`bEnabled`）分组里改。**注意**：脚本新增的蓝图变量默认带“私有”标志（`PropertyFlags` 含 `0x10000`），会导致实例细节面板不显示这些参数；本资产已清除该位并编译保存（踩坑记录见 `knowledge/recipes/blueprint-asset-scripting-limits.md` 第七节）。
- `HTCommon.routes` 改为节流重建（`HTRouteRefreshInterval`，默认 2s，可由怪物蓝图变量覆盖）：按类扫描预制体 + 旧标签 Actor 去重合并；顺序 = `RouteIndex>0`，否则回退 `HT_Route_NNN` 标签，再按对象名；空结果也缓存，避免每帧全量扫描。
- 走点规则（2026-10-29 晚按用户要求调整）：相同序号视为同一“档”，到达某档后、进入下一档时在该档内**随机**选一点（刚到达的点在有其他候选时排除）；到达末档后下一个目标是**首档**，路线循环（不再原路往返）；全局只有一个档时在同档点间随机游走，只有一个点时原地停留。随机用 `math.random`，未显式播种。
- 到点停留（2026-10-29 追加）：`BP_HTWaypoint.WaitTime`（float，秒，0=不停留）。到达后在点旁停止移动，并每帧朝该点箭头方向（点位 Actor 的 Yaw，`K2_SetActorRotation` 设到怪物上）；等待期间检测扫描照常进行（能发现玩家并被拖入追逐）；`WaitTime` 结束才进入下一档。追逐/中止会结束等待（`ReceiveAbortAI` 与重新进入巡逻时重置状态）；当前点被删也会取消等待。`Return` 任务不等待。
- PIE 实测（2026-10-29，会话 `dkcx30kxa3te84`，单机）：导航开局构建成功（`navBuilding=false`、Rebuilt 触发点投影导航网格成功、全程无 `Navigation stalled`）；`GetUGCResourcesFullPath('Asset/.../BP_EffectTriggerSkeletal_Rebuilt.BP_EffectTriggerSkeletal_Rebuilt_C')` 返回正确全路径且 `UE.LoadClass` 得到有效类；DeskTeacherSpawner 刷出班主任后巡逻收集到 4 个路点，运行时写入 RouteIndex=1..4 后按序循环（含 4→1 回首档），`WaitTime=4` 实测停留约 4.0s，停留朝向与该点箭头 Yaw 一致（实测 -180/90/90），`WaitTime=0` 的点不停留；追逐/抓取/返回链路自然触发正常。**注意**：实测的 RouteIndex/WaitTime 是运行时写入，地图数据仍是默认值（0/0），正式使用需在地图实例上配置序号并保存。
- 第二组巡逻点（2026-10-29）：地图新增 7 个点 `RouteName='HT_Route1'`（RouteIndex 1/2 两档），控制 Actor `BP_HTRouteGroup2`（GroupName=`HT_Route1`，`RouteTag` 已改为 `HT_Route` 以匹配班主任标签，初始 `bEnabled=false`）。课桌搜索进度第 7 次解锁：`DeskOutcomeConfig.CountTriggers={[7]='EnableSecondRoute'}`，`DeskSearchService` 在 `Opened` 事件里分发，`DeskTeacherSpawner.OnRouteMilestone` 调 `HTCommon.setGroupEnabled(班主任,'HT_Route1',true)`（老师未刷出时记 `DeskSecondRoutePending`，刷出后补启用）；第一组保持启用，两组路线合并，第二组 1/2 档优先、第一组（RouteIndex 全 0）落在末档随机。<br>现有 5/10 次纸条事件仍在 `FixedSearchOutcomes`，两套配置互不影响。
- 班主任骨架动画（2026-10-29）：`TheHeadTeacher` 的 `AnimListComp.GameplayTagAnimDataListDefault` 原来挂的是僵尸动画（与 ZYZCJY 网格的 `CH_Base_SK_Skeleton` 不匹配，条目上 `ErrorDisplayInfo=动画资源与Mesh不匹配！`），已替换为同骨架资源：`Move.Relax`/`Move.Battle`→`BS_Unarmed_Stand_Idle-Run-Sprint`（BlendSpace）、`Idle.Relax`/`Idle.Battle`→`Unarmed_Stand_Base`、`Hurt`→`Unarmed_Stand_Hit_Head_F`、`Die`→`Rifle_Stand_Death_Montage`（同为 CH_Base 骨架）；写入方式：`条目.ref().set_field('AnimAsset', 对象)` + `AnimListComp.modify()` + `bp.save_package()`（不编译），已用 uasset 二进制确认新旧引用替换。环境雾 `HT_Fog` 见第 3 节。
- 分组语义（`groupStates`）：某组只要存在任一 `BP_HTRouteGroup` 控制即视为“受控”——仅当该控制 `RouteTag` 为空或等于怪物 `HTRouteTag` 且 `bEnabled=true` 时，本怪才巡逻该组；无控制的组按旧规则（组名 == `HTRouteTag` 才默认开启）。多怪分工：不同怪用不同 `HTRouteTag`，组控制里写对应 `RouteTag`。
- 实时性：巡逻/返回 tick 各自调用 `routes()`，刷新后序号自动收敛（`d.index` 钳制）；当前路点被删时先停并打 `route-deleted`，2s 内重建后继续。运行期切换分组用 `HTCommon.setGroupEnabled(p, 组名, enabled布尔值)`——写组控制实例（服务端）的 `bEnabled` 并强制下一 tick 重建；编辑器里改地图、勾选 `bEnabled` 只在下一次 PIE 生效（PIE 运行的是启动时快照），运行中的增删需由 Lua 生成/销毁 Actor 才会被刷新捕获。`Return` 的“最近点”在进入任务时选定，组中途关闭不会改已选返航点。
- 修复（2026-10-29）：`M.next` 原用 `math.huge` 作为“未找到更高档”哨兵，而 `RouteIndex=0` 的点的序值本身就是 `math.huge`，导致存在其它档时这些点永远选不中（表现为第二组解锁后班主任不再回旧巡逻点）；改为 `found` 标志判断，`math.huge` 作为合法档正常参与“下一档/回首档”。
- 未验证：PIE 实际表现（用户指示暂不测试）；DS 上蓝图类 `LoadClass` 可用性（失败会打 `prefab-class` 日志并回退纯标签路径）；`RouteIndex` 全为 0 时的排序依赖对象名，属预期。
- 现状：`962baa3 "map init"` 之后新地图里没有班主任实例、导航体积（`HT_Navigation`/`RecastNavMesh`）与任何巡逻点；恢复巡逻需在新地图放 1 个班主任、导航体积和若干 `BP_HTWaypoint`（必要时加 `BP_HTRouteGroup`）。

## 12. 一句话给接手人

先做第 8 节的遮挡复测（这是唯一还没端到端验证的修复）；期间盯 `[HT_TRACE]` 的 `vis_*`、`catch_*` 行；确认后再关埋点、按团队分支规范把班主任改动与 SearchableDesk 分开提交。
