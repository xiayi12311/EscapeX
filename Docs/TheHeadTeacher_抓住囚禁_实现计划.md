# 班主任"抓住学生 → 扛走 → 囚禁"实现计划

状态：**核心规则已实现并在引擎 Lua 中验证通过**（`CaptureConfig`/`CaptureManager` + 离线与 PIE 双侧测试）；
**引擎层未开工**，因为实测推翻了两个假设（服务器挂接不复制到客户端；冻结效果无法用现有仪器证明），
需要你定 §10.3 的扛人机制并配合一次真人按键测试。视野检测、巡逻、追逐、抓取判定沿用交接记录 4.7 的结论，不改。

## 1. 需求与已确认的四项决策

原始行为描述：将玩家抓住（播放抓取动作）→ 玩家被扛到肩上、无法操作、跟随班主任移动 →
班主任移动向囚禁点（可放置多个，自动选**最近且空闲**的）→ 到达后播放放下动画（表现为捆绑在柱子上，
美术后续实现）→ 玩家被捆绑、无法移动和其它操作 → 囚禁 15 秒后可自行脱离，其它玩家可提前解救。

用户已确认（2026-10-26 问答）：

| # | 决策点 | 选定方案 |
| --- | --- | --- |
| 1 | 流程驱动位置 | **在现有 `BTT_HTCatch` 任务里做阶段状态机**（纯 Lua，不新建行为树任务、不改 BT 源图与运行树） |
| 2 | 抓取是否结算伤害 | **不扣血**，囚禁取代淘汰；`HTDamage` 不再参与抓取结算 |
| 3 | 脱离规则 | **15 秒后玩家可连点挣脱**（不是到点自动解开） |
| 4 | 押送被打断 | **视为怪物无敌，不为"怪物中途被打死"设计分支** |

决策 4 仍保留两处与"打断"无关的正确性清理：怪物 `ReceiveEndPlay`（关卡卸载/销毁）时若玩家仍挂在怪物上必须解挂并恢复；
被囚禁玩家断线/淘汰时释放柱位。这两条是防止状态泄漏，不是失败兜底。

## 2. 引擎依据（全部核到本机版本或原始 JSON/LuaHelper 声明）

| 用途 | 接口 | 依据 |
| --- | --- | --- |
| 玩家"被囚禁"状态 | `UGCPlayerPawnSystem.EnterPawnState(pawn, EPawnState.Imprisonment)` / `LeavePawnState` / `HasPawnState` | `EPawnState` 本机枚举实测存在：`Imprisonment=35`，ToolTip `/UGC* 监禁中`（`ue_read enum:EPawnState`，2026-10-26）；接口声明 `gp-docs/luahelper/Source/Lua/ugc/UGCAPI/UGCPlayerPawnSystem.lua:18-46` |
| 备选冻结（文档明确禁移动/技能/武器） | `UGCPersistEffectSystem.EnterDynamicState(pawn, 'PawnState.Debuff.Dizzy')` / `HasDynamicState` / `InterruptDynamicState` | `wiki/20205.md:69`；`UGCPlayerPersistEffectSystem` 声明 `UGCPersistEffectSystem.lua:84-112` |
| 囚禁期间免伤 | `UGCPlayerPawnSystem.SetIsInvincible(pawn, bool)` / `GetIsInvincible` | `UGCPlayerPawnSystem.lua:83-93`；官方 `api/UGCPlayerPawnSystem-aea1a98e17c9.md:334` |
| 把玩家挂到怪物插槽 | `pawn:K2_AttachToActor(monster, socket, 2, 2, 2, false)`；`pawn:K2_DetachFromActor(2, 2, 2)` | `api/AActor-c7f9082b0344.md:2740 / 2846`；同族写法已在工程实测（`HTCommon.lua:179` 用 `K2_AttachToComponent(...,2,2,2,false)` 挂视野锥） |
| 玩家落位（放下/解绑） | `pawn:K2_SetActorLocation(loc, false, {}, true)`（**必须 bTeleport**；`UGCActorComponentUtility.SetActorLocation` 对 Pawn 实测无效） | `Actor.lua:687`；`knowledge/recipes/chase-moveto-stutter.md:67`、交接记录 §9 |
| 怪物移动/停移 | `UGCGenericCharacterSystem.MoveTo/StopMove/SetMaxSpeed`；`DisableMovement/EnableMovement`（服务器） | `UGCGenericCharacterSystem.lua:51-93`；已在用 `HTCommon.lua:264-271` |
| 怪物动画（抓/放） | `UGCGenericCharacterSystem.PlayAnimMontage / PlayAnimMontageByTag` —— **仅客户端生效** | `UGCGenericCharacterSystem.lua:143-155`；`api/UGCGenericCharacterSystem-80cf9cf133a8.md:545/579` |
| 交互（队友解救、玩家挣脱） | `UClickActorComponentBase`：`CheckFunction(PC, ExtraMessage)` / `ExecuteFunction(PC, ExtraMessage)`，Actor 复制且未勾 `ForceClinet` 时在 DS 执行 | `api/UClickActorComponentBase-8688eb18c4a9.md`；`wiki/20427.md:31-123`；工程实例 `BP_SearchableDesk.lua:30-38` |
| 服务器计时 | `UGCTimerUtility.CreateLuaTimer(delay, fn, loop, name)` / `RemoveLuaTimer` / `IsLuaTimerExistByName`；`UGCGameSystem.GetServerTimeSec()` | `UGCTimerUtility.lua:33-62`；工程实例 `DeskSearchService.lua:87-90`、`TestAutoRevive.lua:86-103` |
| 玩家集合/存活 | `UGCGameSystem.GetPlayerPawnByPlayerKey/GetPlayerControllerByPlayerKey/GetPlayerKeyByPlayerController`；`UGCPlayerStateSystem.IsAlive/IsExit` | `UGCGameSystem.lua:58-85`；`UGCPlayerStateSystem.lua:7-11`；工程实例 `DeskSearchService.lua:44-58` |
| 状态复制 | `GetReplicatedProperties()` 返回字段名 + `OnRep_<字段>`；整表替换做原子复制 | 工程实例 `BP_SearchableDesk.lua:5,40-42`、`DeskSearchService.lua:76` |

### 2.1 明确**不能**用的写法

- `UGCPlayerPawnSystem.ConfirmCarryOther(InPawn, InTargetPawn)` 这条官方"背负"链**不用于本功能**：
  前置条件要求被背者处于**倒地**状态（`IsHaveLastBreathStatus`），且承载方参数类型是 `PlayerPawn`，
  怪物（`BP_UGC_GenericMobPawn_Base_C`）不是它的合法承载方（`UGCPlayerPawnSystem.lua:213-224`）。
  `IsCarriedByAI` 只能查询、不能发起。→ 搬运表现必须自己做挂接。
- 引擎自带 `BTTask_CarryCharacter / BTTask_PutDownCarriedCharacter / BTTask_FindHoldLocation /
  BTTask_LostTomb_BreakHold` 全是 LuaHelper **存根**，归属"流浪地球机械狗""摸金"专用模式，
  无任何 wiki/API 文档说明可用于 UGC 怪物；知识库快照 `failed: []` 但结论仍记为"**未证实存在可用玩法链**"，
  不作为实现依赖（依据：`gp-docs/luahelper/Source/ShadowTrackerExtra/Private/AI/UGC/Task/…`，
  且 `agent 报告`：无 UGC wiki 描述怪物抬走玩家玩法）。
- 快照里没有 `SetIgnorePlayerInput`、`Vector_Distance`、`K2_SetMovementMode`；
  要禁输入只能用 `AController:SetIgnoreMoveInput/SetIgnoreLookInput`（**叠加计数**，恢复用 `ResetIgnoreMoveInput`）
  或 `UGCGameSystem.SetMoveInputEventEnable/SetLookInputEventEnable`（客户端）。

## 3. 待 PIE 实测的两件事（阻塞项，不猜）

**2026-10-26 已实测一轮，结论见 §10；两项仍未结清，状态更新如下。**

1. **`EPawnState.Imprisonment`（监禁中）到底限制什么。** —— **已结清：能阻止真实按键移动。**
   真人按住 W 的五段测量（每段 8 秒，见 §10.5）：基线 3644.4 cm → 置监禁中 **2.8 cm** → 解除 2964.9 cm（恢复行走）
   → 置 Dizzy **65.2 cm**（仅开头惯性）→ 解除 3425.4 cm。基线折合 455 cm/s，与 `MaxWalkSpeed 479.5` 吻合。
   同时 `Enter/Has/Allow/LeavePawnState` 在真实玩家 Pawn 上往返正常，状态会复制到客户端
   （客户端读到 `Imprisonment=true`、`AllowPawnState(Move)=false`）。
   **→ 冻结玩家就用官方 `Imprisonment` 状态，不需要 `SetIgnoreMoveInput` / `MOVE_None` 这类底层锁。**
   仍未测的部分：**开枪/换弹/使用道具是否同样被禁**（`wiki/20205.md:69` 只对 tag 版 Dizzy 明确写了"无法移动、释放技能、使用武器"，
   `Imprisonment` 无文档语义）——囚禁期间玩家还会不会有武器动作，等做完交互再补测一轮。
   另外已作废的仪器教训：注入 `AddMovementInput` 测不出门控（服务器侧基线 0.0 cm、客户端侧置状态后仍 95.7 cm），
   见 §10.4 与 `knowledge/recipes/player-attach-and-state-probes.md`。
2. **课桌那条 `ClickActorComponentBase` 交互在 PIE 里到底通不通。** —— **本轮未测**（要先在关卡里生成交互物并靠人眼看按钮），
   `SearchableDesk_PIE验证记录.md` 的"按钮不显示、`UIInfo` 空、`DSFailed 10001`"仍是未验收状态。
   囚禁点的"解救/挣脱"若走同一链路，必须先证明它可用；不可用则改用
   `TriggerBox`/`OnActorBeginOverlap` 距离自动判定 + 客户端 `UGCInputSystem.BindInputMapping` +
   注册 ServerRPC（`UGCPlayerController:GetAvailableServerRPCs()`，`wiki/203.md:58-132`）作为输入通道。
   两条通道都汇到同一个 `CaptureManager:RegisterStrugglePress/RegisterRescuePress`，只换入口不换逻辑。

3. **新增阻塞项（实测暴露）：服务器侧挂接不复制到客户端。** 见 §10.3——"扛到肩上"的实现方式
   必须由你选一种，不能默认服务器 `K2_AttachToActor` 就够。

## 4. 状态机与服务分层

命名与目录沿用课桌的四层结构（纯逻辑 Manager / 引擎 Service / 客户端 Presentation / 蓝图壳）。

### 4.1 会话状态

```
Grabbing     抓住确认，怪物停移，玩家尚未挂接      → HTPickupDuration 后进入 Carrying
Carrying     玩家挂接在怪物插槽，玩家失去操作      → 选点成功且抵达囚禁点 HTArriveRadius 内
PuttingDown  解挂 + 落位到柱子绑定点 + 放下表现     → HTPutDownDuration 后进入 Imprisoned
Imprisoned   玩家绑定在囚禁点，免伤，不可操作      → UnlockAt = 入此态 + HTImprisonDuration(15)
                                                 此后连点挣脱 或 队友解救
Released     解绑、恢复输入/移动/血量规则、柱位空闲 → 清理
```

`EscortFail`（找不到可达路径/全部占用超时）是 `Released` 的一种 reason，不是新状态。

### 4.2 新增文件

| 文件 | 职责 |
| --- | --- |
| `Script/Gameplay/Capture/CaptureConfig.lua` | 默认参数与囚禁点/会话校验表（纯数据，可离线断言） |
| `Script/Gameplay/Capture/CaptureManager.lua` | **纯 Lua 服务器状态机**：柱位注册、`FindNearestFreePost`、会话推进、挣脱/解救进度、revision/version/interactionId 去旧。所有引擎访问经 `deps` 注入（仿 `DeskSearchManager.new`） |
| `Script/Gameplay/Capture/CaptureService.lua` | 引擎适配层：`Setup/Shutdown`、0.1s 轮询定时器、玩家/距离/存活校验、整表写回 `post.PrisonState` 与 `monster.HTCaptureState`、断线与淘汰清理 |
| `Script/Gameplay/Capture/CapturePresentation.lua` | 客户端表现：读复制状态 → 播放挂接/捆绑表现、进度 UI；不决定任何玩法结果 |
| `Script/AI/HeadTeacher/HTCapture.lua` | 怪物侧阶段执行：调用 `MoveTo/StopMove`、挂接/解挂、置/解 `Imprisonment`、免伤开关；被 `BTT_HTCatch` 每帧驱动 |
| `Script/Blueprint/Prefabs/Interactables/BP_PrisonPost.lua` | 囚禁点蓝图壳：BeginPlay 自注册（带 GameMode 未就绪重试定时器，仿 `BP_SearchableDesk.lua:11-24`）、`Check/OnClick` 两个交互回调、`GetReplicatedProperties` |

### 4.3 需要修改的现有文件

| 文件 | 改动 |
| --- | --- |
| `Script/AI/HeadTeacher/BTT_HTCatch.lua` | 抓取判定通过后不再立即 `FinishExecute(true)`：改为启动 `HTCapture.Begin` 并在 `ReceiveTickAI` 里推进阶段，绑定完成才 Success；`ReceiveAbortAI` 里做解挂恢复（新增 `ReceiveTickAI`，当前任务没有 Tick） |
| `Script/AI/HeadTeacher/HTCommon.lua` | `M.Defaults` 增加 `HTPickupDuration / HTPutDownDuration / HTEscortSpeed / HTArriveRadius / HTImprisonDuration / HTStrugglePresses / HTStruggleInterval / HTRescueDuration / HTCarrySocket / HTPostTag / HTEscortTimeout`；`M.scan` 目标过滤增加"已在会话中的玩家不可再被锁定"；`M.TRACE` 交付前置 false |
| `Script/Blueprint/Prefabs/Monsters/TheHeadTeacher.lua` | `HandleCaughtPlayer` 改为只登记会话（不再 `ApplyDamage`）；`GetReplicatedProperties` 增加 `HTCaptureState`；`ReceiveEndPlay` 增加解挂清理 |
| `Script/Blueprint/UGCGameMode.lua` | `CaptureService.Setup/Shutdown`；`UGC_PlayerKilledEvent` / `UGC_PlayerRespawnEvent` 里清理该玩家会话 |
| `Script/Blueprint/UGCPlayerController.lua` | 断线时 `CaptureService.CancelPlayer`（与现有 `DeskSearch.CancelPlayer` 并列） |

### 4.4 资产（2026-10-26 已创建）

`Asset/Blueprint/Prefabs/Interactables/BP_PrisonPost.uasset`（17 KB，已保存；`ue.bp_lua_get_path` 回读
`exists=true`，已绑定 `Script/Blueprint/Prefabs/Interactables/BP_PrisonPost.lua`）：

| 部件 | 内容 |
| --- | --- |
| 组件 | `DefaultSceneRoot`(SceneComponent)、`PostBody`(StaticMeshComponent，**网格待美术**)、`BindPoint`(SceneComponent)、`RescueArea`(SphereComponent) |
| 变量 | `PostId`(str)、`RescueRadius`(220)、`RescueDuration`(3)、`StrugglePresses`(8)、`BindHeightOffset`(90) |
| 复制 | `bReplicates=true`，CDO 持久化后回读确认 |

两条实测到的编辑限制，别重复踩：

1. **`BindPoint` 的 `RelativeLocation` 脚本设不了**（`unable to set property RelativeLocation`，StructProperty）。
   所以绑定高度改为 `BindHeightOffset` 变量 + Lua 挂接后 `K2_SetRelativeLocation` 补偿；
   你也可以在蓝图里直接把 `BindPoint` 拖高，二者取其一。
2. **`ClickActorComponentBase` 没有配**：它要往 `ClickButtonInfo` 数组里填嵌套结构
   （`CheckFunction: FClick_CheckFunctionName`、`ExcuteFunction: FClick_ExcuteFunctionName`、`UIInfo: FClickUIInfo`），
   而这正是课桌至今没配通的地方（`UIInfo` 空 → 按钮不显示）。盲配只会产出一个看着完整、实则不可用的资产，
   所以 `BP_PrisonPost.lua` 里 `CheckRescuePrisoner/OnClickRescuePrisoner/CheckBreakFree/OnClickBreakFree`
   四个回调先写好待接，**组件与 `UIInfo` 请在编辑器里配**（或等课桌那条链路先验收通）。
3. **变量类型关键字坑（本机构建）**：`blueprint_add_member_variable(bp,'PostId','str')` 建出来的是
   **IntProperty**（默认 0），而交接记录 §9 第 3 条写的正确关键字是 `string`；
   并且这个构建里 **`blueprint_remove_member_variable` 与 `blueprint_set_variable_default_value` 不存在**
   （`py:guide blueprint` 列了但模块没有），所以建错的变量**既删不掉也改不了类型**，重新 add 会报同名冲突。
   结论：`PostId` 只能是 int。Lua 里 `0` 是**真值**，原先的 `actor.PostId and actor.PostId ~= '' and actor.PostId or name`
   会让所有没填编号的柱子都拿 id=`0` → **第二根柱子必然 `DUPLICATE_POST`**。已改为按类型+取值解析
   （正整数编号优先，否则回落到对象名），并加了回归用例 `posts left at the blueprint default PostId=0 still register separately`。
4. **CDO 上取不到 SCS 组件**：`getattr(cdo,'BindPoint')` 返回 None（组件模板不是实例属性）。
   组件本身在蓝图里存在（`get_blueprint_components` 可见），运行期能否从 Lua 取到要靠 PIE 证实——
   课桌的 `self.SearchArea`/`a.Drawer` 证明这类 SCS 组件在运行期可取，但这是**待验证项**，不是已证事实。

关卡摆放：本轮**不往 `UGCmap` 写测试点**；PIE 验证改为运行时 `SpawnActor` 生成囚禁点，避免污染关卡文件。
UI：`WBP_DeskSearchProgress` 的复制件仍未做（进度条要等交互通道定了再画）。


## 5. 参数（默认值，全部可被蓝图变量覆盖）

沿用 `HTCommon.M.config(p, key)` 的读法：实例上有同名蓝图变量就用它，否则用 Lua 默认。

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `HTCarrySocket` | `headSocket` | 扛人挂接插槽；美术补肩部插槽后只改蓝图值。当前怪物只有 `headSocket` 实测可用 |
| `HTPickupDuration` | 0.6 | 抓起动作阶段（动画资源未到位时为纯计时） |
| `HTPutDownDuration` | 0.6 | 放下动作阶段 |
| `HTEscortSpeed` | 300 | 押送速度（介于巡逻 150 与追逐 500 之间） |
| `HTArriveRadius` | 120 | 判定"已到囚禁点"的胶囊表面间距 |
| `HTImprisonDuration` | 15 | 获得挣脱资格所需秒数（决策 3） |
| `HTStrugglePresses` | 8 | 挣脱所需连点次数 |
| `HTStruggleInterval` | 0.15 | 挣脱连点最小间隔（防单帧多事件刷满；对齐官方 `BTTask_LostTomb_BreakHold.InPressInterval` 的思路） |
| `HTRescueDuration` | 3 | 队友解救所需持续秒数 |
| `HTEscortTimeout` | 20 | 押送失败上限：超过则就地释放并记 `escort_fail`（**待确认**，见 §7） |

## 6. 验收清单

离线（lupa，`Tests/run_capture_tests.py`，沿用课桌测试风格与 runner 约定）：

- 选点：多个柱位时取最近空闲；全占用返回 `NO_FREE_POST` 且**不占用任何柱位**
- 占用与释放：同一柱位不能同时有两个会话；释放后重新可选
- 阶段推进：按注入时钟逐段推进，时钟回退/重复 Update 不产生二次释放
- 挣脱：`UnlockAt` 前点击一律无效；`HTStruggleInterval` 内的连点不计数；攒够次数只释放一次
- 解救：非本人、存活、距离内才有效；进度随 `Update` 超时衰减/取消；解救与挣脱同时到点只结算先到的
- 去旧：`ResetVersion`/`InteractionId`/`Revision` 任一过期即整条忽略（对齐 `DeskPresentation.Apply` 的判据）
- 断线/淘汰：会话清理且柱位归还；怪物 EndPlay 时挂接状态被解除（用 mock 断言调用序）

PIE（需重启调试会话，逐项写进 `TheHeadTeacher_囚禁玩法_PIE验证记录.md`）：

1. 抓住后 DS 日志出现 `Grabbing → Carrying`，玩家 Pawn 世界坐标随怪物移动（读 `K2_GetActorLocation` 连续采样）
2. 被扛玩家在客户端**无法移动、无法开枪**，画面跟随怪物（人工确认一次）
3. 怪物到达最近空闲囚禁点并放下；第二个柱位存在时验证"最近且空闲"选择正确
4. `Imprisoned` 期间读 `HasPawnState(Imprisonment)` 为 true、`GetIsInvincible` 为 true，受击不掉血
5. 15 秒前连点无效；15 秒后连点 8 次成功挣脱，柱位回到空闲
6. 队友在柱旁持续解救 3 秒可提前放出；被绑者本人不计入解救
7. 断线、淘汰、怪物销毁三种清理路径无残留（柱位不永久占用、玩家不永久失能）
8. 押送全程 `catch_skip reason=GAP/TELEPORT` 不出现，抓取轮次不重复结算（`ProcessedSequenceId` 语义不变）

## 7. 待确认（不阻塞开工，但上线前要你定）

- **囚禁点全部占用 / 无可达路径**：当前默认"重试到 `HTEscortTimeout=20s`，超时就地释放玩家并记 `escort_fail`"。
  若你希望"全部占用时怪物带着玩家一直等"或"直接不抓"，改这一条规则即可，状态机不需要重写。
- **队友解救的输入形式**：默认"靠近柱子持续交互（进度条）"。若要改成"连点"，与挣脱共用同一进度接口。
- **被囚禁玩家的免伤**：默认整段 `Carrying + Imprisoned` 免伤。若希望"绑着也能被打死"，去掉 `SetIsInvincible` 调用即可。
- `HTTargetBoundsHeightRatio` 尚未做成蓝图变量（交接记录遗留项），与本功能无关，不在此处处理。

## 8. 提交拆分

仓库在 `feature/searchable-desk`，工作区已混有课桌功能改动。本功能单独成提交：

- 提交 A：`Script/Gameplay/Capture/*` + 囚禁点蓝图/Lua + 关卡测试摆放
- 提交 B：`BTT_HTCatch` / `HTCommon` / `TheHeadTeacher` / `UGCGameMode` / `UGCPlayerController` 的接线改动
- 提交前：`HTCommon.M.TRACE = false`；不推主分支、不强推、不重写共享历史（AGENTS.md）

## 9. 风险登记（2026-10-26 实测后更新）

| 风险 | 状态与处置 |
| --- | --- |
| `Imprisonment` 状态语义未知（可能不禁输入） | **已结清**：真人按住 W 实测 3644.4 → **2.8 cm**，解除后 2964.9 cm（§10.5）。冻结就用这个官方状态。未测项仅剩"武器动作是否一起禁"，见 §3.1。 |
| 服务器挂接不复制到客户端 | **实测成立**（§10.3）。扛人表现必须按 §10.3 的 A/B/C 之一实现，由你选定后再写引擎层。 |
| 挂接玩家在 DS 上表现异常（`ds-player-mesh-detached` 记录过玩家网格脱离） | 该坑是"读**玩家自己**的插槽坐标"，我们读的是**怪物插槽**（已由 `MeshComponentUpdateFlag=0` 保证 DS 更新），实测 12 次采样距离恒 113.5，未复现。**不要**改回读玩家插槽。 |
| 被绑玩家自己无法点交互（状态把 UI 一起禁了） | 未测（依赖 §3.2）。若不可用，挣脱输入改走客户端 `BindInputMapping` + ServerRPC；两条通道汇入同一进度函数。 |
| `EnterDynamicState` 同 Tag **叠加计数**，`LeaveDynamicState` 需配对 | 声明见 `UGCPersistEffectSystem.lua:93-105`；优先用 `EPawnState`（无计数语义）；若用 tag 则用 `InterruptDynamicState` 强制清并保证成对调用。 |
| 行为树在长任务期间被更高优先级中止 | 现有树只有单一 Sequence，无并行分支；`ReceiveAbortAI` 仍做解挂恢复，避免状态泄漏。 |
| 课桌交互链路本身未验收，囚禁点复用同链路 | 仍未验收。未通过前囚禁点代码只写 Manager/Service 与距离自动判定，不依赖按钮。 |
| 探针把玩家塞到怪物身边会触发它现有的 300 抓取伤害 | 实测发生一次（由 `TestAutoRevive` 复活）。跑挂接/位置类探针前先临时禁用抓取伤害或远离怪物。 |

## 10. 实测记录（2026-10-26，PIE 会话 `dkcx30iakiqe1u`，DS + 客户端 Lua）

部署：`Script/Gameplay/Capture/CaptureConfig.lua`、`CaptureManager.lua` 已复制进实际工程并逐文件 SHA256 一致；
`Asset/` 下 `.lua` 数为 0；PIE 正常启动，班主任 AI 照常巡逻。两个新模块各刷一条
`Actor Lua file ... can't find correspond Bluepirint` **告警**——这与 `HTCommon.lua`、课桌四个模块、
`ue_enum_custom.lua` 完全同类（纯模块文件没有对应蓝图，属既有正常噪音，非新引入问题）。

### 10.1 状态机在引擎 Lua 中成立

`UGCGameSystem.UGCRequire` 能加载两个模块；用引擎自己的 Lua 跑完整流程 41 条断言全通过，覆盖：
两柱位注册/去重/`POST_LOCATION_REQUIRED`、按距离排序取最近、`nil` 选项走 Defaults（`StrugglePresses=8`、
`RescueDuration=3`、`RescueRadius=220`、`StruggleInterval=0.15`）、阶段时序（`PickupDuration` 后才计入押送时限）、
占用/释放/重抢、`MarkArrived` 幂等、`unlockAt=+15s`、15 秒前点击一律 `NOT_YET`、间隔内连点 `TOO_FAST`、
攒够 8 次只释放一次、自救 `SELF_RESCUE`、距离校验不过 `RESCUER_TOO_FAR`、解救中途离开自动取消并可换人、
`RESCUED`/`BROKE_FREE` 两种释放、快照字段与 `Revision` 单调、事件顺序、`ReleaseAll`。
另外单独补测了被抓阶段死亡即释放：`death during Grabbing releases=true reason=PLAYER_DEAD busy=false`。

前一轮 10 个 FAIL **全部是探针自身缺陷**（多返回值只接两个、把注入时钟往回拨、`dead` 标记泄漏未复位），
已修正重跑；不是状态机问题。教训记在 §10.4。

### 10.2 冻结/免伤接口实测

| 项 | 实测结果 |
| --- | --- |
| `EPawnState` | 是真表：`Imprisonment=35 Stun=32 Carring=50 Frozen=45 Move=0` |
| `EnterPawnState(pawn, 35)` | `true`；随后 `HasPawnState=true`、`AllowPawnState(Move)=false`；`LeavePawnState` 后 `false` |
| Tag 合法性 | `PawnState.Debuff.Dizzy`/`PawnState.Imprisonment`/`PawnState.Buff.Invincible` = true；`PawnState.Debuff.Imprisonment`/`Frozen`/`Stun` = **false** |
| `EnterDynamicState('PawnState.Debuff.Dizzy')` | `true`，`HasDynamicState=true`，`LeaveDynamicState=true` |
| `SetIsInvincible(true)` + `ApplyDamage(20)` | 伤害返回 **0.0**，血量 100 → 100，**免伤成立**；`GetIsInvincible=true`，可恢复 |
| `UGCPlayerStateSystem` | `IsAlive=true`、`IsExit=false` 可直接用于校验器 |
| 移动读数 | `CharacterMovement` 在 Lua 可达且 `DisableMovement`/`SetMovementMode` 可调用；`cm:GetMovementMode` **不存在**（每次误访问都会刷一条 `[LuaException]`）；`MaxWalkSpeed` 恒 479.5 |

### 10.3 挂接（扛人）实测——设计岔路

服务器侧 `pawn:K2_AttachToActor(monster, 'headSocket', 2, 2, 2, false)` 调用成功；怪物以 150 速度走动时，
**服务器的玩家坐标与头部插槽距离 12 次采样恒为 113.5**（挂接在服务器确实生效、跟随）。
同一时间窗客户端采样自己的 Pawn：`20995,28720,190` **一动不动**，与插槽距离从 705 涨到 1385
——**服务器侧挂接不复制到客户端**，玩家自己屏幕上不会被"扛起来"。
引擎自带背负组件里那个 `PostAttachmentReplication`（`USTCharacterCarryOtherComp`）正是为此存在，但它是引擎内部件、未对 UGC Lua 开放。

附带两条可读性事实：`GetAttachParent`/`K2_GetAttachParent`/`K2_GetAttachSocketName` 在 Lua 里**都不存在**，
挂接与否只能靠几何距离判断；解挂与复位用 `K2_DetachFromActor(2,2,2)` + `K2_SetActorLocation(...,bTeleport=true)`
实测可精确复原（`delta=0.0`）。

可选实现（待你定，见 §7）：

- **A 客户端自己做挂接**：服务器只维护囚禁会话与复制状态，**由被扛玩家的客户端**把自己的 Pawn
  `K2_AttachToActor` 到怪物插槽（与课桌"复制状态 → 客户端表现"同一套路），解绑时对称 detach + 落位。
  表现最省，但服务器不持有位置真值，押送路线判定仍以怪物为准。
- **B 服务器逐帧钉位置**：服务器每 tick 用 `K2_SetActorLocation(bTeleport=true)` 把玩家钉在肩上，
  位置真值在服务器；风险是客户端预测会与之打架，需要先确认移动锁得住。
- **C 只做逻辑不做大戏**：玩家不真的挂上去，服务器钉在地面坐标（或怪物脚边），捆绑表现交给后续美术动画。

### 10.4 探针脚本自身的坑（写给下一轮）

1. 多返回值必须全接：`return true, count, need` 只写 `local a,b=` 会让断言假失败。
2. 注入时钟**只能前进**：把 `now` 往回拨会让状态机静默停在原阶段（`grabUntil` 已在过去之后才满足），
   不报错、不释放——探针脚本里出现"FAIL 但逻辑看着对"先查这个。
3. 复用 `dead`/`rescuer` 之类的 mock 表要显式复位，否则后续 `StartSession` 因 `PLAYER_BUSY`/`NO_POST`
   返回的**不是 id 而是 reason 字符串**，会把一整段断言连带污染。
4. 实验性地把玩家硬塞到怪物身边会触发它自己的抓取伤害；本轮由此淘汰了一次玩家，
   由工程内 `TestAutoRevive` 原地复活（日志 `revived at (20830,28740,190), 1313cm from the death spot`），
   收尾已确认存活、无残留状态。**跑探针前先想清楚会不会撞到在跑的 AI。**

### 10.5 真人按键失能测量（PIE 会话 `dkcx30iakist2v`，玩家全程按住 W）

| 段 | 条件 | 位移（8 秒内最大值） |
| --- | --- | --- |
| A | 无状态基线 | **3644.4 cm**（≈455 cm/s，与 `MaxWalkSpeed 479.5` 吻合） |
| B | `EnterPawnState(pawn, EPawnState.Imprisonment)` | **2.8 cm**，读数 `imp=true, allowMove=false` |
| C | `LeavePawnState` 后 | 2964.9 cm（马上恢复行走 → 证明按键没松、也没撞墙） |
| D | `EnterDynamicState(pawn,'PawnState.Debuff.Dizzy')` | **65.2 cm**（只有开头惯性滑行） |
| E | `LeaveDynamicState` 后 | 3425.4 cm |

`hp` 全程 100、`alive=true`；结束时 `imprisonment=false dizzy=false allowMove=true invincible=false`、
探针定时器已停。**判据设计要点**：必须是 A/B/A 对称结构——只看 B 是 2.8 cm 不能下结论，
要有 C/E 的恢复位移证明"玩家确实在按键、地形允许通行"，才能把 B 的归因落在状态上。
测试期间把该只怪物的 `HTDamage` 在**运行时**置 0（防止现行 300 抓取伤害把人打死中断测量），
不落盘，重启 PIE 即恢复。

## 11. 交付口径（2026-10-26 第二轮）

**引擎层已写完并离线验证**：`CaptureService`（服务器适配：定时器、校验器、复制写入、服务器挂接/解挂/落位、
冻结与免伤配对）、`CapturePresentation`（客户端：只给自己 Pawn 挂接、状态清空即解挂）、
`HTCapture`（怪物阶段机：选点占用、押送复用 `H.moveTick`、到点上报、完成/中止清理）、
`BP_PrisonPost`（自注册、两个交互回调对、`PrisonState` 整表同步）、
以及 `BTT_HTCatch`（抓到后转为长任务 Running + Tick + Abort 清理）、`TheHeadTeacher`
（`HandleCaughtPlayer` 返回 started/reason、`HTCaptureState` 同步 + OnRep、EndPlay 清理）、
`HTCommon`（新增 8 个 HT* 默认值、`M.busyPlayer` 过滤已被抓/被绑玩家）、
`UGCGameMode`（Setup/Shutdown、淘汰时清会话）、`UGCPlayerController`（断线清会话）。

离线：`Tests/capture_flow_test.txt` **17 组**集成用例全过（挂接调用序、冻结/免伤恰好一次、到点绑定+偏移、
挣脱八次只释放一次、自救/距离不过/中途离开、客户端只挂自己、Abort 释放柱位、无空闲柱位超时释放，
以及下面 §12 每条评审缺陷的针对性回归）；
回归：班主任 24、课桌 3 套、复活 19 全部 exit 0。**顺带修掉两个真实缺陷**：快照缺 `CarrySocket`
（会让挂接走到"无目标"并立刻释放）、会话转 `Imprisoned` 后怪物 `HTCaptureState` 永不清空。
另外把班主任测试骨架里"UGCRequire 一律返回 HTCommon"的 mock 改成按路径解析——否则新增模块在测试里是假的。

**PIE 端到端验证被挡**：启动 PIE 需要保存脏包，而脏的是 `BP_SearchableDesk`（你正在改的课桌蓝图，
外加一个开着的抽屉模型），`SaveDirtyPackages failed or left dirty packages: content=1`。
我不替你保存没做完的资产。你保存或关闭该资产后，我按计划用运行时 `SpawnActor` 生成囚禁点跑全链路
（抓→扛→押送→绑→15 秒→连点挣脱），不改 `UGCmap`。

仍未验证：`Imprisonment` 是否连武器动作一起禁；`ClickActorComponentBase` 交互链路；
**Lua 表整表同步到客户端**这一条本身（本轮设计的地基，按课桌同一机制实现，PIE 里必须实测）。


## 12. 两轮独立代码评审的结论与处置（2026-10-26）

派了两个不带我结论的评审：一个查引擎层六个文件，一个查接线改动。**逐条对代码复核后确认成立并修复的**（每条都加了针对性回归）：

| # | 缺陷 | 修复 | 回归用例 |
| --- | --- | --- | --- |
| 1 | Carrying 挂接失败后没 `return`，嵌套的 Released 之后又被过期 Carrying 快照覆盖 → 受害者客户端**永久挂在怪物上** | 失败分支补 `return`；`publishMonster` 加 `SessionId` 归属判断，不再清别的会话状态 | `a failed carry attach leaves no stale carrying state on the monster` |
| 2 | `byMonster` 进入 `Imprisoned` 后不释放 → 只要有一个囚犯没放出，**这只怪终生抓不了第二个人**（AI 侧与管理层认知相反） | `_enter('Imprisoned')` 释放忙标记、保留引用以便最终清理 | `the carrier is freed once the player is bound and can capture again` |
| 3 | 押送失败（超时/中止/柱位被移除）也把玩家瞬移到柱位，违反 §7"就地释放" | 快照加 `WasBound`，只有真绑过才落位 | `a failed escort releases the player where they stand, not at the post` |
| 4 | 每根柱子的 `RescueRadius/RescueDuration/StrugglePresses` 全部失效（`postOptions` 永远传 nil） | `ClaimPost` 时把**柱子真正配置过的**项写进会话（未配置不覆盖，注册期不再强塞默认值） | 同上 + `capture_test` 的柱位参数用例 |
| 5 | 客户端绑柱不应用 `BindHeightOffset`，两端差 90cm | `CapturePresentation.grab` 挂完后同样施加偏移 | `presentation ignores stale revisions and mirrors the bind height` |
| 6 | `Grabbing` 那 0.6 秒既不冻结也不复检距离，玩家可跑出抓取再到 Carrying 被挂走 | 冻结/免伤提前到 `SessionStarted`（抓住即失能） | `catch stays Running...`（断言 Grabbing 阶段已冻结、尚未挂接） |
| 7 | 释放只认"当场查到的 Pawn"，取不到就静默跳过全部清理 | 会话级 Pawn 句柄记忆（`pawnFor`），取不到时打日志 | 评审项，PIE 再验复活换 Pawn 场景 |
| 8 | `CapturePresentation` 完全不校验 Revision，§6 承诺的"去旧"不存在 | `accepts()` 按 actor 单调 Revision 拒绝过期载荷 | 同上 presentation 用例 |
| 9 | 囚禁点自注册：actor 失效时定时器不注销；注册失败也删定时器 → 柱位静默不可用 | 失效即注销；失败有限次重试（50 次）后**明确报错**并停止 | 代码走查（BeginPlay 路径需 PIE 确认） |
| 10 | `d.capture` 句柄泄漏 → `ALREADY_CAPTURING` 永久拒抓（NO_GAMEMODE 分支不清、handler 抛错不回滚、Execute 不复位 `Capturing`、Abort 里诊断先于清理可能抛错跳过清理） | `NO_GAMEMODE` 清句柄；trace 参数不再无条件求值（`trace()` 内 `pcall`）；Execute 复位 `Capturing`；`not started` 时回滚会话；Abort 先清理再诊断 | `an incomplete capture start cannot leave an orphan session on the pawn` |
| 11 | 绑定完成那一瞬间怪物被销毁会**误放已绑玩家** | `C.cancel` 若会话已 `Imprisoned` 只丢句柄、不释放（人属于柱子） | `a monster destroyed after the bind must not release the prisoner` |
| 12 | 淘汰事件顺序使自动复活落在柱子而不是死亡点 | `UGCGameMode` 里先 `TestRevive.onKilled` 再清会话 | 顺序改动，PIE 复核 |
| 13 | `Struggle/Rescue/CancelPlayer` 直接调 `GetPlayerKeyByPlayerController` 无 `pcall`，与全文件风格不一致 | 统一 `keyOf()`；并新增 `Service.CanRescue` 让 Check 与 Execute 用同一套判据（否则按钮可点、点了被拒、什么也不发生） | `the post callbacks take the engine Click_Param and gate by role` |
| 14 | 交互回调签名错：我写的是 `(PC, ExtraMessage)`，引擎原生 `AssignNew` 生成的是**单个 `FClick_Param`**（课桌已按此改过，见 `SearchableDesk_PIE验证记录.md` 第 92–94 行） | 四个回调改为 `(Click_Param)` 并从结构体取 `PlayerController` | 同一用例直接以 `{PlayerController=...}` 调用回调 |
| 15 | 客户端 `TheHeadTeacher` BeginPlay 不应用已存在的 `HTCaptureState`（迟到加入） | 非权威端 BeginPlay 调 `Presentation.Carrier` | PIE 重连用例 |

**明确不修的（附理由，不是遗漏）**：

- 怪物死亡路径（`BPDie` 不清会话）：按你的决策"怪物无敌，不用考虑打断"。已知后果写清楚：若尸体延迟销毁且 BT 仍在 tick，玩家可能被"尸体"带着走，最长 `HTEscortTimeout=20s` 后就地释放。PIE 里若观察到，再按实际情况决定。
- `M.TRACE` 仍为 `true`：§8 已列为提交前动作，不是缺陷。
- 8 个新 `HT*` 参数**没有对应蓝图变量**，所以"同名蓝图变量可覆盖"目前是空能力，调参要改代码——记为待办，不做假开关。

**PIE 必验清单（合并两轮评审）**：整表同步是否真的触发客户端 OnRep；两阶段换绑（怪物→柱子）在最坏情况下的单帧脱挂；押送中三种中止（BT 重启/直接销毁/尸体未销毁）；被绑后被脚本复活或换 Pawn 的清理；断线重连是否残留挂接；`ClickActorComponentBase` 的 Check 到底在 DS 还是客户端执行；以及每柱参数改值后是否真生效。


## 13. PIE 端到端验证当前被编辑器状态挡住（2026-10-26）

`ue_pie start` 两次失败：`SaveDirtyPackages failed or left dirty packages: maps=0 content=1`。定位过程与结论：

- 脏的不是本项目资产。`BP_PrisonPost`/`BP_SearchableDesk`/`UGCmap` 三个包 `package_is_dirty=false`。
- 脏的是三个**引擎自带模板**：`/Game/Actor_Timeliness/Elevator/Blueprint/{BP_DoorBaseInter_BW, BP_DoorBaseOuter_BW, BP_ElevatoBase_BW}`。
  它们在磁盘上没有散装文件——`/Game` 由 `Content/Paks/core.pak`（48 GB）挂载，**根本保存不了**，所以启动前的保存必然失败。
  这种脏通常是加载期"遗留资产自动升级"打的标记，不是任何人的编辑内容（本项目对它们**零引用**：
  `get_asset_referencers` 为空、`UGCmap` 的 44 个依赖里没有 Elevator）。
- 尝试过且全部不通的路径（2026-10-26 实测）：
  1. `reload_blueprint` **不清脏**（前后都是 `dirty=true`）；
  2. `unload_package(路径)` 报 `argument is not a UPackage`；传包对象报
     **"以下资产已经被修改并且无法卸载……保存这些资产即可将它们卸载"** —— 引擎把"保存"作为卸载的前提；
  3. 保存等于往 `ShadowTrackerExtra/Content/Actor_Timeliness/Elevator/Blueprint/` 写三个散装 `.uasset`
     覆盖 pak 版本，属改动共享资源，**权限策略两次拒绝**（第二次已获用户授权 unload，但引擎只给"保存"这条路，
     我没有绕过拦截）；
  4. `py:` 面里没有"清脏标记"或"忽略脏包启动 PIE"的接口。
- 工程自身资产未被波及：`BP_PrisonPost`/`BP_SearchableDesk`/`UGCmap` 实测 `dirty=false`；
  那三个模板包对本工程**零引用**（`get_asset_referencers` 为空、`UGCmap` 的 44 个依赖里没有 Elevator）。
- **只有人能做的三种解法**：① 在编辑器里点 Play，弹"保存失败"时选**不保存**（PIE 照常起来，最快）；
  ② 重启编辑器（脏标记随进程消失）；③ 由你手动保存那三个模板包（之后删掉那三个文件即可还原 pak 行为）。
  PIE 一起来我就按"注册 → 整表同步 → 抓→扛→押送→绑→15s→连点挣脱"跑完；两个验证驱动已写好并做过
  语法与未定义名检查，囚禁点用运行时 `SpawnActor` 生成，**不写 `UGCmap`**。
