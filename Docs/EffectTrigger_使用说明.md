# 通用效果触发器

蓝图：`Asset/Blueprint/Prefabs/Interactables/BP_EffectTrigger`；脚本：`Script/Blueprint/Prefabs/Interactables/BP_EffectTrigger.lua`。

`TriggerArea` 为触发盒，调整其尺寸和相对位置；`EffectMesh` 是要演出的网格体；`EffectSequence` 是蓝图内的 Actor Sequence，必须为 EffectMesh 制作轨道。当前默认立方体及开门音效是测试占位，正式使用时替换。Actor Sequence 的音效轨道和单独音效不要重复配置同一声音。

每个关卡实例可编辑：

- `EffectEnabled`：启用检测。
- `EffectAudience`：0 所有相关客户端；1 仅进入的玩家。
- `EffectTriggerMode`：0 每次进入；1 整局一次；2 每个玩家一次。
- `EffectCooldown`：全局冷却秒数，默认 0；冷却内的进入不会延迟补发，需离开再进入。
- `EffectSoundPath`：AkAudioEvent 对象路径，空字符串表示不播放独立音效。

服务端检测重叠，按玩家及规则判定，通过可靠 multicast 通知客户端；客户端按接收范围过滤、从头播放 Actor Sequence 并播放挂在 Actor 上的音效。设置了 Always Relevant 以覆盖全体已连接客户端。演出期间新连接或此前未收到 Actor 的客户端不会追播；本实现不改变服务端 Mesh 碰撞，不应作为影响玩法的机关权威状态。

对同一玩家多个碰撞组件的重叠去重，只有从完全离开到再次进入才可再次触发。服务端 `TryTriggerEffect(playerKey)` 是扩展入口（仍受开关、次数及冷却约束），`ResetEffectTrigger()` 清空触发次数及冷却，不重置区域占用，也不会自动触发区域内玩家。重复触发时客户端停止当前序列并从头播放；独立音效不会被自动停止。

已验证：单客户端区域进入、动画、音效、重复触发和整局一次；双客户端每人一次、仅触发者播放，以及全体播放。若实例属性、声音或动画不可用，先排查资产绑定和客户端日志。



## 抽象父类与子类（待运行时验证）

新增 `BP_EffectTriggerBase`，已启用 `bGenerateAbstractClass`，只包含触发盒和公共参数；不应放入地图。`BP_EffectTriggerExample` 继承该父类，自己持有 `EffectMesh` 和 `EffectSequence`，可作为制作具体效果的结构样例。子类同名 Lua 引用父类脚本并复制方法表，使各蓝图拥有独立的类元数据。每个新子蓝图需在其同名 Lua 中按样例引用父类，编辑新子类自己的网格与序列。

此父子结构尚未在 PIE 验证，不能把已有头盔实例视为已迁移。原 `BP_EffectTrigger` 和地图中的现有实例保留原样，仍有独立脚本；验证父子结构的脚本绑定、区域事件、序列、音效及联网后，才能迁移现有头盔并收敛旧脚本。不要把父类直接放进地图，也不要直接编辑父类为某个具体演出添加模型和动画。


## 骨骼网格触发器（待配置和 PIE 验证）

`BP_EffectTriggerSkeletal` 继承抽象父蓝图，自带 SkeletalMeshComponent `EffectMesh` 与 ActorSequenceComponent `EffectSequence`。在子蓝图里给 `EffectMesh` 配置骨骼网格，在 `EffectSequence` 为 `EffectMesh` 添加动画轨道并选择兼容骨骼的 Animation Sequence，同时添加 Transform 等所需的 Actor Sequence 轨道。将动画片段与其他轨道对齐到同一时间轴，触发时一次 StartPlay 驱动两种表现，避免重复对同一网格体调用单独 PlayAnimation 与动画轨道相互覆盖。注意核对根运动与变换轨道，避免重复位移。声音仍通过 `EffectSoundPath` 配置；若序列已包含同一音效，则清空该路径避免重复播放。

该蓝图已配置为班主任蓝图当前的 ZYZCJY_AT_M_Jacket_1001 骨骼网格；计划使用 `Unarmed_Stand_Walk_F` 作为占位行走动画，已确认其与网格共用 `CH_Base_SK_Skeleton`；动画及变换轨道尚未配置，父子 Lua 的实际运行时绑定也尚未验证。新 PIE 会话需要验证区域进入、动画与变换同步、音效、重复触发，以及播放范围。当前服务端仅判定触发，客户端表现不应作为权威碰撞或游戏状态。


