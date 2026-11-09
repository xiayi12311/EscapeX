# 玩家可推拉箱子原型：设计与实现方案

- 文档日期：2026-11-09
- 项目：EscapeX
- 编辑器：4.18.1-0+++UE4+Release-4.18
- 知识库快照：2026-10-22
- 状态：设计稿，尚未实施
- 目标载体：`/EscapeX/Asset/Blueprint/Prefabs/Interactables/BP_PushPullCrate`

## 1. 目标与边界

### 1.1 原型目标

实现一个可被玩家从四个侧面推、拉的箱子：

1. 玩家靠近箱子并看向可用侧面时，出现与现有课桌一致的交互按钮。
2. 交互按钮不带读秒、进度圆环或进度条。
3. 点击按钮后，玩家进入推拉动作状态，先播放 OnPosition，再进入推拉待机。
4. 玩家使用移动轴前/后（W/S、手柄或移动端摇杆的前后分量）执行推、拉。
5. 推拉时箱子按服务端计算的方向与速度移动；玩家动画只表现，不以动画根运动驱动箱子。
6. 允许一个箱子同时被多名玩家操作。
7. 同向参与者越多，箱子移动越快；反向参与者的贡献相互抵消。
8. 箱子顶部可站立，玩家可使用原生翻越/攀爬登上箱顶；推拉与攀爬互相排斥。

### 1.2 原型不包含

- 箱子倾倒、翻滚、旋转或物理挤压。
- 多箱子连锁推动、箱子把另一个箱子撞飞。
- 斜坡、台阶、悬崖和重力下落场景。
- 车辆、怪物或 AI 推箱。
- 箱子损坏、重量变化、材质摩擦系数和动态音效。
- 上下半身分层动画、战斗动作与推拉动作混合。
- 对现有课桌系统进行大规模重构。

## 2. 已核对资源与现有基础

### 2.1 推拉动作序列

编辑器 AssetRegistry 中已存在以下 `AnimSequence`，骨骼均为 `CH_Base_SK_Skeleton`，均未启用 Root Motion：

| 资源名 | 用途 | 时长 |
| --- | --- | ---: |
| `CG009_Puzzle_OnPosition` | 进入操作位的起手动作 | 1.333 s |
| `CG009_Puzzle_Idle` | 推拉待机循环 | 1.533 s |
| `CG009_Puzzle_PushStart` | 推的起手 | 1.333 s |
| `CG009_Puzzle_Push` | 推的循环 | 2.100 s |
| `CG009_Puzzle_PushStop` | 推的停止 | 0.800 s |
| `CG009_Puzzle_PullStart` | 拉的起手 | 0.600 s |
| `CG009_Puzzle_Pull` | 拉的循环 | 1.000 s |
| `CG009_Puzzle_PullStop` | 拉的停止 | 0.733 s |

完整资源路径统一位于：

```text
/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_*.CG009_Puzzle_*
```

资源中存在 `cG009`/`CG009` 大小写差异时，以实际资产名 `CG009_` 为准。所有路径写入 `PushPullConfig.lua`，不在业务代码中散落硬编码。

### 2.2 可复用交互形式

现有课桌通过以下文件实现了“准星聚焦、描边、世界锚点、按钮展示”：

- `Script/Gameplay/Interaction/DeskFocusPresentation.lua`
- `Script/Gameplay/Interaction/InteractionConfig.lua`
- `Script/MIG/Blueprint/AI_PatientMonster/WBP_Interact_patient.lua`
- `Script/MIG/UI/Hospital/WBP_Interact.lua`

原型复用同一套 `WBP_Interact_patient`：

- 左侧按钮文本改为“推拉”；已接入时改为“松开”。
- 右侧按钮隐藏。
- 每次刷新显式调用 `SetProgress(nil)`，不显示圆环或进度。
- 使用现有描边、目标切换、世界锚点与 DPI 投影逻辑。
- 不修改课桌的业务服务，只新增箱子自己的聚焦表现模块，避免原型阶段影响已验收课桌。

### 2.3 玩家输入与攀爬依据

- `UGCInputSystem.GetInputValue(WorldContext, InputTag)` 为客户端接口，可读取指定 InputTag 当前值。
- 推拉模式读取 `Input.Move.MoveForward`，不使用相机朝向重新解释输入，避免拉箱时相机转向导致方向跳变。
- 原生角色翻越开关为 `bVaultIsOpen`；开启后，玩家可使用 `PawnState.Action.Vault` 完成翻越。
- 推拉期间使用 `UGCPersistEffectSystem.SetDynamicStateDisabled` 获取和释放动作锁；它是按标签引用计数的，不会覆盖其他系统持有的同类锁。

### 2.4 箱体模型候选

原型可优先使用：

```text
/Game/Arts_Scenes/Meshs/Objects/Mesh_woodencrate_05.Mesh_woodencrate_05
```

若美术比例不合适，可保持逻辑碰撞尺寸不变，仅调整显示网格的缩放。逻辑上使用独立 `UBoxComponent`，不依赖木箱网格的复杂碰撞。

## 3. 玩法规则

### 3.1 玩家流程

```text
靠近箱子并看向侧面
    -> 出现“推拉”按钮与箱子描边
    -> 点击按钮
    -> 服务器校验玩家位置并分配动态抓握点
    -> 播放 OnPosition
    -> 进入 Idle
    -> 移动轴向前：PushStart -> Push 循环
    -> 移动轴向后：PullStart -> Pull 循环
    -> 回中：PushStop/PullStop -> Idle
    -> 再点“松开”或发生异常
    -> 播放停止动作、解除动作锁、恢复普通移动
```

### 3.2 控制约定

- 进入推拉状态后，玩家身体朝向所操作的箱子侧面。
- `Input.Move.MoveForward > +Deadzone` 解释为“推”。
- `Input.Move.MoveForward < -Deadzone` 解释为“拉”。
- 绝对值小于死区时解释为无推拉输入。
- `MoveRight` 在此模式下忽略，玩家不能侧向绕箱。
- 镜头自由观察不改变推拉方向。
- 推拉期间禁止跳跃、翻越、冲刺、蹲、趴、持枪、开火、瞄准、换弹、拾取和技能等动作；保留看向和 UI 输入。
- 松开操作按钮是主动退出入口；死亡、断线、箱子销毁、被抓取或进入无法操作状态时由服务器强制退出。

### 3.3 连续四面操作与多人占用

不使用固定“1 号位 / 2 号位”抓握槽。抓握点由玩家的实际站位动态计算，玩家可以站在箱子四周的任意位置进入推拉：

- 箱子保留前、后、左、右四个逻辑侧面，用于选择角色朝向和推力方向。
- 玩家位置先投影到箱体水平包围盒，再取最近的侧面作为 `FaceIndex`。
- 玩家沿该面的实际切向位置记录为归一化坐标 `GripU`，因此沿整条边都可以接入，而不是只能站在几个固定点。
- 抓握点到箱面的距离由 `GripStandOff` 控制；它需要同时匹配玩家胶囊半径和推拉动画的手部位置。
- 每个参与者拥有独立的 `ParticipantId + Grip`，不存在可被客户端直接指定的公共槽位号。
- 同一玩家同时只能接入一个箱子。
- 多人之间使用连续最小间距约束 `MinGripSpacing`，而不是离散槽位。
- 若玩家想站的位置离另一名参与者过近，服务器只在同一面内寻找最近的可用点，最大自动偏移 `AutoSpreadMax`；找不到才拒绝进入。
- 自动偏移是为了避免两个角色胶囊和动作重叠，不代表恢复固定槽位；玩家仍可沿面任意选择站位。
- 参与者可独立进入、推、拉和退出，不要求整组同步。

推荐初始参数：

```lua
MaxParticipants = 8       -- 仅作为安全上限，不作为每面固定容量
MinGripSpacing = 70       -- 两个抓握点之间的最小世界水平距离，cm
EdgeMargin = 28           -- 抓握点距离箱子转角的最小留白，cm
AutoSpreadMax = 40        -- 站位冲突时最多自动错开，cm
AutoSpreadStep = 5        -- 候选点搜索步长，cm
GripStandOff = 45         -- 玩家抓握点到箱面的水平距离，cm
```

“任意位置”在动画表现上的边界：当前只有四条正向推拉动作，没有斜向动作。因此玩家可以站在任意连续位置，但角色仍按最近侧面朝向；箱角处选择主导侧面，不做斜向推拉动画。如果要求角色真正面向箱角斜推，需要新增对应动作资源，不在本原型范围。

## 4. 总体架构

### 4.1 分层

| 层 | 职责 | 执行端 |
| --- | --- | --- |
| `BP_PushPullCrate` | 箱体、碰撞、动态抓握点计算、复制状态、注册与 OnRep | 场景 Actor |
| `PushPullManager` | 纯状态机：参与者、动态抓握点、输入、动画状态、合力计算 | 服务器逻辑，GameMode 持有 |
| `PushPullService` | 引擎适配：验证玩家、移动箱子、处理注册/销毁/断线 | 服务器 |
| `PushPullAnimation` | 本地动作序列状态机，播放和恢复玩家动画 | 每个客户端 |
| `PushPullPresentation` | 本地 Pawn 与抓握锚点跟随、远端参与者动画应用 | 每个客户端 |
| `PushPullFocusPresentation` | 准星检测、描边、没有进度条的按钮 | 本地玩家客户端 |
| `PushPullConfig` | 资源路径、距离、间距、速度、时间、动作锁、抓握参数 | 数据配置 |
| `UGCPlayerController` | 请求进入、同步输入、请求退出 | RPC 边界 |

### 4.2 服务端权威边界

客户端只提交：

- 想操作哪个箱子。
- 当前推拉输入：`-1 / 0 / +1`。
- 请求序号与会话号。

服务器负责：

- 玩家身份、存活、距离、朝向、连续抓握点、互斥和容量校验。
- 推拉状态推进。
- 多人贡献合成。
- 箱子碰撞扫描与实际位置。
- 强制释放、超时和清理。

客户端不能提交目标速度、箱子目标位置、占用人或动画完成结果。

### 4.3 建议新增文件

```text
Script/Gameplay/PushPull/PushPullConfig.lua
Script/Gameplay/PushPull/PushPullManager.lua
Script/Gameplay/PushPull/PushPullService.lua
Script/Gameplay/PushPull/PushPullAnimation.lua
Script/Gameplay/PushPull/PushPullPresentation.lua
Script/Gameplay/PushPull/PushPullFocusPresentation.lua
Script/Blueprint/Prefabs/Interactables/BP_PushPullCrate.lua
Tests/pushpull_manager_test.txt
```

并小范围接入：

```text
Script/Blueprint/UGCPlayerController.lua
Script/Blueprint/UGCGameMode.lua
EscapeX.ugcproj
```

## 5. 数据模型

### 5.1 箱子状态

建议由 `BP_PushPullCrate.CrateState` 作为一个整体复制表：

```lua
CrateState = {
    CrateId = "Crate_A",
    SessionId = 12,
    Revision = 34,
    Enabled = true,
    MotionSpeed = 62.5,
    MotionDirX = 0.0,
    MotionDirY = 1.0,
    Participants = {
        [10001] = {
            PlayerKey = 10001,
            ParticipantId = "p10001-crateA-3",
            FaceIndex = 1,
            GripU = 0.37,          -- 0..1，沿该面的连续位置
            GripStandOff = 45.0,
            Phase = "Active",      -- Entering / Active / Releasing
            Intent = 1,            -- -1 Pull, 0 Neutral, 1 Push
            AnimState = "Push",
            AnimRevision = 8,
        },
    },
}
```

约束：

- 只在参与者、输入、动画阶段或运动状态发生变化时替换整表，不逐 Tick 复制。
- 箱子位置由 Actor Movement Replication 同步；状态表不携带逐帧位置。
- `Revision` 用于拒绝旧消息。
- `SessionId` 用于箱子重建或重置后丢弃旧会话消息。

### 5.2 动态抓握点

“抓握位”在实现中不是场景里的固定 Socket，也不是每面预摆的几个 Arrow，而是一份每名参与者独立持有的连续抓握契约：

```lua
Grip = {
    ParticipantId = "p10001-crateA-3",
    FaceIndex = 1,       -- 0 Front / 1 Right / 2 Back / 3 Left
    GripU = 0.37,        -- 该面的归一化切向位置
    GripStandOff = 45.0, -- 从箱面法线向外的距离
}
```

四个面只定义基准法线、切向轴和角色朝向：

| 面 | 向外法线 | 切向轴 | 切向范围 |
| --- | --- | --- | --- |
| Front | `(1,0,0)` | `(0,1,0)` | 箱体 Y 方向半宽 |
| Back | `(-1,0,0)` | `(0,-1,0)` | 箱体 Y 方向半宽 |
| Left | `(0,-1,0)` | `(-1,0,0)` | 箱体 X 方向半宽 |
| Right | `(0,1,0)` | `(1,0,0)` | 箱体 X 方向半宽 |

给定箱体世界变换后，计算：

```text
usableHalf = faceHalfLength - EdgeMargin
tangentOffset = lerp(-usableHalf, +usableHalf, GripU)
gripLocal = faceCenter + tangentAxis * tangentOffset + outwardNormal * GripStandOff
gripWorld = CrateTransform.TransformPosition(gripLocal)
bodyYaw = CrateYaw + FaceYaw
```

抓握点只存在于状态表中，不需要为每名玩家动态创建 Actor 或组件。表现层根据 `CrateTransform + Grip` 每帧计算世界位置；玩家挂接时保存相对于箱体的同一局部偏移即可。

#### 5.2.1 接入位置解析

服务器收到进入请求后：

1. 将玩家水平位置转换到箱体本地空间。
2. 与箱体水平包围盒比较，选出最近的侧面作为 `FaceIndex`。
3. 将超出侧面的切向坐标夹到 `[EdgeMargin, FaceLength - EdgeMargin]`，换算为 `GripU`。
4. 生成首选抓握点。
5. 检查其与所有现有参与者抓握点的水平距离是否都大于等于 `MinGripSpacing`。
6. 若冲突，则在当前面内按 `AutoSpreadStep` 向左右搜索最近的有效点，最大偏移 `AutoSpreadMax`。
7. 找到有效点后冻结 `FaceIndex + GripU + GripStandOff`，返回 `ParticipantId` 给客户端。
8. 找不到则返回 `NO_FREE_GRIP`，不会静默把玩家放到另一个面。

候选点排序只看与玩家期望位置的切向距离，不读取客户端的 PlayerKey、抓握点或目标速度。

#### 5.2.2 箱角处理

- 玩家靠近箱角时，以本地空间中占优的轴选择最近侧面。
- 角色仍按该侧面的正向姿态播放动作，箱角不生成斜向抓握点。
- 相邻面的玩家也参与 `MinGripSpacing` 的世界距离检查，避免两人在转角处身体重叠。
- 若箱角附近空间不足，玩家沿当前面自动错开；仍不足则拒绝。

#### 5.2.3 进入移动中的箱子

`Grip` 固定在箱体本地空间，因此箱子移动时抓握点和参与者一起移动。是否允许在箱子已有速度时新加入由 `AllowJoinWhileMoving` 控制：

```lua
AllowJoinWhileMoving = false
JoinMaxSpeed = 15
```

原型建议先关闭移动中加入，先验证静态进入和多人跟随；验证稳定后再打开并复测 OnPosition、角色跟随和远端表现。

## 6. 服务端玩法状态机

```text
Unregistered
    -> Idle
    -> Entering
    -> Active(Neutral)
    -> Active(Pushing) <-> Active(Pulling)
    -> Releasing
    -> Idle
```

### 6.1 状态说明

- `Idle`：箱子存在，无参与者。
- `Entering`：服务器已分配并冻结动态抓握点，等待 OnPosition 完成，不施加移动力。
- `Active(Neutral)`：播放待机动作，读取输入，不施加移动力。
- `Active(Pushing/Pulling)`：读取输入并参与合力计算。
- `Releasing`：不再施加移动力，但保留抓握点直到停止动作完成，防止其他玩家立刻抢占造成动画重叠。
- 死亡、断线、销毁等强制释放可跳过停止动画，立即清理抓握点与动作锁。

### 6.2 进入校验

服务器收到进入请求后依次校验：

1. 箱子有效、已启用且状态版本有效。
2. 玩家 Controller、Pawn、PlayerKey 有效。
3. 玩家存活、未离场、未被抓取、未处于其他推拉会话。
4. 玩家位于箱体外侧交互带内，且到箱体表面的水平距离不超过 `SurfaceInteractionBand`。
5. 玩家躯干高度处于侧面交互带内，不能站在箱顶请求侧面推拉。
6. 玩家位于某一侧面主导区域，且朝向与该面夹角不超过 `MaxFacingAngle`。
7. 能解析出与其他参与者保持 `MinGripSpacing` 的动态抓握点。
8. 同一请求序号未被处理，避免重放。

任一项不满足都明确拒绝并返回稳定原因码：

```text
CRATE_DESTROYED
CRATE_DISABLED
PLAYER_UNAVAILABLE
PLAYER_BUSY
TOO_FAR
WRONG_FACE
NO_FREE_GRIP
STALE_REQUEST
```

### 6.3 输入租约

客户端在推拉输入变化时发送一次 `ServerSetPushPullIntent`，并在非零输入期间以 `InputHeartbeat = 0.15 s` 周期续租。

- `IntentLease = 0.35 s`。
- 超时未收到续租时，服务器把该玩家输入归零并进入停止动作。
- 输入 RPC 不得超过 `MaxInputRpcRate = 15 Hz`，超限丢弃并记录，不改变箱子速度。
- 会话号或请求序号不匹配时直接拒绝。

这样既不会每帧发包，也不会因一次丢包或客户端卡死让箱子永久移动。

## 7. 多人合力模型

### 7.1 单个参与者贡献

设玩家所站面的向外单位法线为 `n`：

- 推：贡献方向 `d = -n`，即把箱子推离玩家。
- 拉：贡献方向 `d = +n`，即把箱子拉向玩家。
- 中性：不贡献力。

因此：

- 同一面两人同时推，两个同向单位向量相加。
- 对侧一人推、另一人拉，若二者制造的箱子运动方向相同，也会叠加加速。
- 对侧两人互相推，方向相反，力抵消。

### 7.2 合力与速度

```text
force = sum(participantDirection)
magnitude = length(force)
if magnitude < OppositionDeadzone then targetSpeed = 0
else
    dir = normalize(force)
    targetSpeed = min(MaxSpeed, BaseSpeed * magnitude)
end
```

默认参数建议：

| 参数 | 默认值 | 说明 |
| --- | ---: | --- |
| `BaseSpeed` | 55 cm/s | 单人推拉速度 |
| `MaxSpeed` | 220 cm/s | 最多 4 人同向时的上限 |
| `Acceleration` | 240 cm/s² | 从静止到目标速度 |
| `Deceleration` | 360 cm/s² | 回中或抵消时减速 |
| `OppositionDeadzone` | 0.15 | 防止反向力在零附近抖动 |
| `MotionTickRate` | 20 Hz | 服务端运动更新频率 |

箱子实际速度使用加速/减速平滑，不允许反向瞬间跳变。若速度为 0，保留最后方向仅用于动画，不推动 Actor。

### 7.3 移动方式

- 箱体根组件 `Mobility=Movable`。
- `bReplicates=true`。
- 服务端使用带 Sweep 的 `SetActorLocation` 移动。
- 只使用水平方向，Z 保持不变。
- 箱子不旋转、不倾倒、不因受力产生角速度。
- 碰到墙、其他箱子、关门或不可站立障碍时，当前 Tick 位置不推进，速度归零并记录 `CRATE_BLOCKED`。
- 原型不实现箱子之间的连锁推动；其他箱子视为阻挡。

## 8. 玩家动作状态机

第一版原型采用 Lua 驱动的全身动作状态机，不直接改原生玩家 AnimBP。原因：

- 推拉资源是非 Root Motion 的普通 `AnimSequence`。
- 工程已有通过 `USkeletalMeshComponent:PlayAnimation` 播放角色动作并恢复动画模式的实现路径。
- 当前工程内没有可直接修改的玩家推拉 AnimBP 资产，先不引入一个与原生角色动画系统耦合的新 AnimBP。

动作状态：

```text
None
  -> OnPosition
  -> Idle
  -> PushStart -> PushLoop -> PushStop -> Idle
  -> PullStart -> PullLoop -> PullStop -> Idle
  -> Restore
```

### 8.1 状态表

| 状态 | 动画 | 循环 | 进入条件 | 离开条件 |
| --- | --- | --- | --- | --- |
| `OnPosition` | OnPosition | 否 | 进入请求被接受 | 1.333 s 后 |
| `Idle` | Idle | 是 | OnPosition 完成或停止动作完成 | 推拉输入变化 |
| `PushStart` | PushStart | 否 | Idle 中向前输入 | 1.333 s 后 |
| `PushLoop` | Push | 是 | PushStart 完成 | 输入回中或反向 |
| `PushStop` | PushStop | 否 | PushLoop 退出 | 0.800 s 后 |
| `PullStart` | PullStart | 否 | Idle 中向后输入 | 0.600 s 后 |
| `PullLoop` | Pull | 是 | PullStart 完成 | 输入回中或反向 |
| `PullStop` | PullStop | 否 | PullLoop 退出 | 0.733 s 后 |
| `Restore` | 无 | - | 主动/强制退出 | 恢复原动画模式 |

### 8.2 方向切换

- `PushLoop` 收到反向输入：先进入 `PushStop`，停止完成后若反向输入仍有效，自动进入 `PullStart`。
- `PullLoop` 收到反向输入：先进入 `PullStop`，停止完成后若反向输入仍有效，自动进入 `PushStart`。
- 停止动作期间暂缓新动画切换，但记录最后一次输入；不得丢失玩家持续按住的意图。
- `Entering` 与 `OnPosition` 期间输入只缓存，不产生移动力。

### 8.3 循环动画速率

循环动作播放速率与当前箱子实际速度关联：

```text
LoopRate = clamp(ActualSpeed / BaseSpeed, MinLoopRate, MaxLoopRate)
```

建议 `MinLoopRate=0.75`、`MaxLoopRate=1.6`。起手和停止动作固定 `1.0`。这样多人同向加速时，玩家动作也会更明显地加快。

### 8.4 播放与恢复要求

- 进入前保存 `Mesh:GetAnimationMode()`。
- 播放使用 `Mesh:PlayAnimation(sequence, looping)`。
- 循环状态使用 `Mesh:SetPlayRate(rate)` 调整。
- 退出时先停止当前推拉动作，再恢复原动画模式和普通移动。
- 强制释放、死亡、断线、箱体销毁也必须走幂等恢复，不能只清业务状态而留下播放模式或动作锁。
- 失败时明确记录缺少资源、播放失败或恢复失败，不以普通待机动画静默替代。

## 9. 玩家与箱子对齐、跟随

### 9.1 进入时对齐

- 服务器解析并冻结 `Grip` 后，把玩家标记为 `Entering`。
- 拥有者客户端在 `AlignDuration=0.15 s` 内把玩家位置和朝向平滑对齐到抓握锚点。
- 位置不对齐到箱子中心，而是对齐到该参与者冻结的 `GripU + GripStandOff` 所对应的世界抓握点。
- 对齐期间锁定移动，镜头仍可观察。
- OnPosition 动画和锚点跟随同时开始；动画完成前不施加箱子运动力。

### 9.2 箱体移动时的玩家跟随

已知本工程实测边界：仅在服务器把玩家挂接到移动物上，拥有者客户端不会自动看到同样的挂接效果。因此推拉采用与现有搬运相同的双层方案：

1. 服务器保留逻辑挂接关系，并把服务器 Pawn 保持在抓握锚点。
2. 拥有者客户端把自己的 Pawn 挂接/对齐到复制的抓握锚点。
3. 两端进入推拉时设置 `MovementMode=None`，并暂停 CharacterMovement 的组件 Tick，避免附着后相对位置持续漂移。
4. 退出时先解除附着，再恢复原 MovementMode、组件 Tick 和碰撞设置。
5. 对抓握中的玩家关闭其胶囊与箱体之间的移动碰撞，防止箱体扫掠时把玩家弹飞。
6. 对同一面多个玩家保留玩家之间的碰撞；若 PIE 证明胶囊互顶导致抖动，需停下来确认是否关闭玩家间碰撞，不在代码里私自兜底。

进入/退出过程必须能够重复执行：第二次释放不得再次解除其他系统刚加上的锁，也不得把 MovementMode 恢复成错误值。

## 10. 攀爬设计

### 10.1 使用原生翻越

- 在玩家配置或角色预设中确认 `bVaultIsOpen=true`。
- 箱子逻辑高度建议为 100 至 120 cm，顶部为平坦、可站立碰撞面。
- 玩家从任一侧靠近并使用原生翻越即可登上箱顶。
- 箱体碰撞应提供稳定顶面，不使用只有视觉网格而没有碰撞的装饰箱。

### 10.2 与推拉状态互斥

- 玩家处于推拉会话时禁用 `PawnState.Action.Vault`，不能一边抓着箱子一边翻上顶部。
- 玩家站在箱顶时不显示侧面“推拉”按钮；服务器也拒绝侧面进入请求。
- 未参与推拉的玩家可以在箱子移动时尝试翻越。翻上箱顶后应随箱子一起移动，不得出现脚底滑移。

### 10.3 移动平台验证要求

箱体是服务端扫掠移动的 Movable Actor，而玩家顶部站立涉及 CharacterMovement 的移动底座处理。必须在多人 PIE 中单独验证：

- 玩家静止站在箱顶，箱子移动时是否跟随。
- 玩家在箱顶走动时，是否保持站立的局部坐标。
- 跳跃落在移动箱顶时是否稳定。
- 两名玩家同时在箱顶时是否相互挤压或掉落。
- 箱子停止后是否能正常翻下。

若原生移动底座无法带走玩家，不进入隐藏兜底；停止实施并依据实测结果确定新的明确方案（例如单独同步顶部乘客的位移），经用户确认后再继续。

## 11. 交互按钮与聚焦表现

### 11.1 显示条件

本地聚焦层每 `DetectInterval=0.1 s` 检查：

- 准星射线首先击中 `BP_PushPullCrate`，没有被墙或其他物件遮挡。
- 命中面属于四个侧面之一。
- 玩家到箱体表面的水平距离不超过 `SurfaceInteractionBand`，且能解析出可用抓握点。
- 玩家不在箱顶、不在翻越中、未死亡、未被抓取。
- 玩家没有接入其他箱子。
- 当前面存在满足 `MinGripSpacing` 的动态抓握点。

满足后显示：

- 箱子描边。
- 左按钮文本“推拉”。
- 无进度条、无圆环。
- 按钮世界锚点使用本次预测的 `GripWorld`，因此玩家沿同一条边移动时按钮也会跟随，不会跳向固定槽位。
- 已接入时按钮文本“松开”；此时“松开”按钮始终对该玩家可见，并跟随自己的动态抓握点，不要求玩家继续用准星照着箱子。

### 11.2 复用方式

`PushPullFocusPresentation` 复用课桌模块的：

- 中央准星射线与阻挡判断。
- 世界坐标到 UI 锚点投影。
- `DrawOutline`。
- `WBP_Interact_patient` 异步创建与销毁。
- Pawn 变化监控和定时器清理方式。

但不复用课桌读秒、搜索服务、进度圆环和搜索状态表。

### 11.3 按钮行为

- `OnPressed`：未接入时发送进入请求；已接入时发送退出请求。进入和退出都不要求按住按钮。
- `OnReleased`：不发送推拉输入，也不结束会话。
- 每次 UI 刷新调用 `SetProgress(nil)`。
- 服务器拒绝时关闭本地待确认状态并显示短提示，不能假装已进入。
- 旧请求、旧会话或旧目标回包不得改变当前 UI。

## 12. 网络协议

### 12.1 客户端到服务器

```lua
ServerRequestPushPull(crate, requestSeq)
ServerSetPushPullIntent(crate, sessionId, intent, requestSeq)
ServerReleasePushPull(crate, sessionId, requestSeq)
```

约束：

- `requestSeq` 单调递增且为正整数。
- `intent` 只允许 `-1/0/1`。
- 服务器从 Controller 取真实 PlayerKey，不接受客户端传入 PlayerKey。
- 每次 RPC 校验会话号、版本、玩家状态与动态抓握点。
- 迟到的进入/退出请求必须被拒绝。

### 12.2 服务器到客户端

- 箱体状态表通过 `OnRep_CrateState` 分发。
- 本地拥有者客户端处理玩家对齐、动作和 UI。
- 远端客户端根据参与者状态播放对应角色动画。
- 服务器不发送逐帧输入或逐帧动画时间；循环动作由客户端按状态启动，起手/停止由状态时间与本地资源时长推进。
- 新加入客户端只读取当前稳定状态，不补播历史 OnPosition 或停止动画。

## 13. 生命周期与异常

必须覆盖：

- 玩家死亡/进入濒死：立即移除参与资格，释放动态抓握点，强制恢复动作与移动。
- 玩家断线：Controller 断开事件中清理会话。
- 玩家被抓取：推拉会话结束，禁止与抓捕锁定互相覆盖。
- 箱子销毁：所有参与者强制退出，清理 UI、描边和定时器。
- 回合重置/游戏结束：清空所有箱子会话，必要时箱子回到初始位置。
- 旧动画回调：会话号或动画版本不匹配时忽略。
- 按钮目标切换：不会把旧箱子的请求转移到新焦点。
- 箱子被阻挡：继续播放推拉动作，但 Actor 不穿模；记录一次可诊断日志。
- 反向力抵消：不左右抖动，目标速度为零，状态仍可表现为用力推拉。

所有清理必须幂等。动作锁、碰撞忽略、MovementMode、组件 Tick、动画模式和 UI 都采用“记录原值再恢复”，清理两次不得产生第二次副作用。

## 14. 可配置参数

全部配置放入 `PushPullConfig.lua`，按功能分组：

### 14.1 资源

```lua
Animations = {
    OnPosition = "/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_OnPosition.CG009_Puzzle_OnPosition",
    Idle = "/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_Idle.CG009_Puzzle_Idle",
    PushStart = "/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_PushStart.CG009_Puzzle_PushStart",
    Push = "/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_Push.CG009_Puzzle_Push",
    PushStop = "/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_PushStop.CG009_Puzzle_PushStop",
    PullStart = "/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_PullStart.CG009_Puzzle_PullStart",
    Pull = "/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_Pull.CG009_Puzzle_Pull",
    PullStop = "/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_PullStop.CG009_Puzzle_PullStop",
}
```

### 14.2 交互与动态抓握

```lua
SurfaceInteractionBand = 90
TraceDistance = 350
MaxFacingAngle = 60
MaxParticipants = 8
MinGripSpacing = 70
EdgeMargin = 28
AutoSpreadMax = 40
AutoSpreadStep = 5
GripStandOff = 45
AllowJoinWhileMoving = false
JoinMaxSpeed = 15
```

### 14.3 运动

```lua
BaseSpeed = 55
MaxSpeed = 220
Acceleration = 240
Deceleration = 360
OppositionDeadzone = 0.15
MotionTickRate = 20
```

### 14.4 输入

```lua
InputTag = "Input.Move.MoveForward"
InputDeadzone = 0.15
InputHeartbeat = 0.15
IntentLease = 0.35
MaxInputRpcRate = 15
```

### 14.5 动作与跟随

```lua
AlignDuration = 0.15
MinLoopRate = 0.75
MaxLoopRate = 1.6
```

这些参数不得在多个文件中各写一份；动画时长优先从实际资源读取，配置值只作为安全上限或日志校验依据。

## 15. 验收清单

### 15.1 基础交互

- [ ] 沿箱子四个面任意位置靠近，均能出现一个“推拉”按钮。
- [ ] 按钮、描边和世界锚点正确，墙后不显示。
- [ ] UI 全程没有进度条或圆形进度。
- [ ] 点击后进入 OnPosition，再稳定进入 Idle。
- [ ] 重复点击、旧回包和目标切换不会产生第二个会话。
- [ ] 点击“松开”后恢复普通移动和正常动画。

### 15.2 单人推拉

- [ ] 向前输入播放 PushStart，随后循环 Push，箱子远离玩家。
- [ ] 向后输入播放 PullStart，随后循环 Pull，箱子靠近玩家。
- [ ] 回中播放对应 Stop，再进入 Idle。
- [ ] 推拉反向时先停止再起手，不出现动作硬切或方向瞬跳。
- [ ] 动画速率跟随实际箱子速度变化。
- [ ] 箱子撞墙不穿模，玩家不脱手、不被弹飞。

### 15.3 多人

- [ ] 两名玩家可同时接入同一箱子。
- [ ] 两名玩家同向时速度高于单人，且不超过上限。
- [ ] 相邻面同向操作时箱子沿合力方向移动，不抖动。
- [ ] 反向操作时速度相互抵消，不产生快速来回翻转。
- [ ] 一名玩家退出后其余玩家继续操作，速度按剩余贡献更新。
- [ ] 任意两名参与者的抓握点始终满足 `MinGripSpacing`，动作与胶囊不重叠。
- [ ] 同一玩家不能同时操作两个箱子。
- [ ] 延迟和丢包下服务器位置一致，无客户端各自推箱子。

### 15.4 攀爬

- [ ] 未接入玩家可从侧面翻上箱顶。
- [ ] 箱顶可站立、可走动、可跳下。
- [ ] 站上箱顶后侧面“推拉”按钮消失，服务器拒绝侧面请求。
- [ ] 玩家推拉期间不能翻越。
- [ ] 箱子移动时箱顶玩家随箱子移动，无明显滑移或掉落。
- [ ] 从箱顶退出/死亡/箱子销毁时无残余碰撞和 UI。

### 15.5 生命周期

- [ ] 死亡、断线、被抓取、重置、箱子销毁均清理会话和动作锁。
- [ ] 旧动画回调不会改变新会话。
- [ ] 全部释放后箱子状态回到无参与者，不持续移动。
- [ ] 重连或晚加入能正确看到箱子位置与当前参与者。

## 16. 分阶段实施顺序

### 阶段 0：资源与基础场景验证

- 创建 `BP_PushPullCrate`，放入测试地图。
- 设置 Movable、复制、BoxCollision 和基于周长的动态抓握点计算；不创建固定槽位。
- 验证 8 个动画序列能在玩家骨骼上完整播放。
- 验证原生 Vault 可登上箱顶。

### 阶段 1：单人接入与动作状态机

- 实现聚焦、按钮、进入/退出 RPC。
- 实现 OnPosition、Idle、推拉起手、循环和停止。
- 确认无进度条、动作锁能正确恢复。

### 阶段 2：单人服务端移动

- 实现输入租约、合力模型、扫掠移动和碰撞阻挡。
- 验证正常推拉、反向、停止、撞墙。

### 阶段 3：多人接入与跟随

- 增加动态抓握点、会话、参与者状态和输入贡献。
- 验证同向加速、反向抵消、退出后速度更新。
- 验证双客户端下玩家跟随、箱子位置和动画一致。

### 阶段 4：攀爬与移动平台

- 验证箱顶站立、翻越和移动跟随。
- 明确处理箱顶玩家与推拉玩家的优先级。

### 阶段 5：清理与回归

- 覆盖死亡、断线、被抓取、箱子销毁、回合重置。
- 执行现有课桌、抓捕与启动流程回归，确认没有共享动作锁冲突。
- 更新 `Docs/` 实现记录和 `knowledge/recipes/` 中可复用结论。

## 17. 风险与待实测项

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 角色全身单节点动画与原生移动动画切换 | 退出后可能残留动画模式 | 保存/恢复 AnimationMode，完整生命周期测试 |
| 服务端挂接不复制到拥有者客户端 | 玩家看不到自己随箱移动 | 沿用搬运的拥有者本地挂接方案 |
| MovementMode=None 后 CharacterMovement Tick 仍造成漂移 | 抓握相对位置漂移 | 按既有搬运实测方案暂停组件 Tick，并读回验证 |
| 移动箱顶的 CharacterMovement 底座 | 箱顶玩家滑移或掉落 | 阶段 4 专项 PIE，不静默改方案 |
| 动态抓握点间距不足 | 同侧玩家胶囊或动作重叠 | 使用 `MinGripSpacing`、箱角距离检查和有限自动错位 |
| 动画手部位置与抓握点不一致 | 穿模或悬空 | 抓握点由动画调校，不只用箱体几何中心 |
| 输入 RPC 频率和网络延迟 | 箱子运动抖动或持续 | 输入租约、心跳上限、服务端平滑 |
| 箱子状态整表复制的频率 | 带宽和动画跳变 | 只在状态变化时更新，不逐帧复制 |
| 阻挡时仍播放推拉动作 | 玩家看起来在推但箱子不动 | 这是有意的用力反馈；记录 blocked 并允许松开 |
| 箱子网格尺寸与碰撞不一致 | 攀爬和抓握点偏差 | 逻辑 BoxCollision 独立定义，网格仅做视觉适配 |

## 18. 需要实施前确认的事项

以下不影响总体架构，但会影响手感和资源制作：

1. 箱体最终尺寸和视觉资源是否采用 `Mesh_woodencrate_05`，还是另做统一顶面的原型箱。
2. `MinGripSpacing`、`EdgeMargin` 和 `AutoSpreadMax` 的最终手感值；容量由箱体边长和间距自然决定，不再写死每面人数。
3. 循环动画速率是否随箱子实际速度加速；本设计默认开启。
4. 攀爬是否允许发生在箱子移动过程中；本设计默认允许，但必须通过阶段 4 验收。
5. 箱顶玩家是否应阻挡其下方玩家继续推拉；本设计默认不阻断，只禁止顶面玩家自己发起侧面推拉。

## 19. 本地依据

- `Docs/SearchableDesk_交互课桌设计.md`：课桌交互、按钮和服务器权威设计。
- `Docs/UnifiedInteraction_migration_plan.md`：统一聚焦、描边、世界锚点和按钮替换方案。
- `Script/Gameplay/Interaction/DeskFocusPresentation.lua`：本地准星、目标选择、UI 生命周期。
- `Script/MIG/Blueprint/AI_PatientMonster/WBP_Interact_patient.lua`：复用按钮形式；`SetProgress(nil)` 隐藏圆环。
- `Script/Gameplay/Capture/CapturePresentation.lua`：玩家动画播放与恢复、拥有者客户端挂接的工程实测路径。
- `knowledge/recipes/player-attach-and-state-probes.md`：服务器挂接与客户端挂接边界、MovementMode/Tick 实测结论。
- `knowledge/gp-docs/wiki/20427.md`：ClickActorComponent 与交互按钮组件说明。
- `knowledge/gp-docs/wiki/20290.md`：输入映射与 W/S 移动轴说明。
- `knowledge/gp-docs/api/UGCInputSystem-a8bf997e5ae3.md`：`GetInputValue` 参数和客户端生效范围。
- `knowledge/gp-docs/wiki/248.md`：`bVaultIsOpen` 与原生翻越功能。
- `knowledge/gp-docs/wiki/20205.md`：`PawnState.Action.Vault` 等角色状态标签。
- `knowledge/gp-docs/luahelper/Engine/Source/Runtime/Engine/Classes/Components/SkeletalMeshComponent.lua`：`PlayAnimation`、`SetPlayRate` 声明。

本文是设计和实施前验证计划，不宣称上述游戏逻辑、多人跟随或移动箱顶攀爬已经通过 PIE。实施完成后应另写实现记录与验证记录。