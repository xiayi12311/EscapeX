# Run 可复制 AS 盒体触发组件

## Intent / acceptance
用户要求在 /EscapeX/Asset/Sequences/Run 建筑内添加可直接复制的盒体组件，蓝图内编辑位置、大小并独立指定已有 AS。用户确认：所有玩家同步播放；每个盒体整局只触发一次。

## Scope / change necessity
新增 BoxComponent 派生组件蓝图 BP_ASBoxTrigger 及对应 Lua，在 Run 中放置一个默认指向 ActorSequence 的组件。不改变两段已有 AS 的轨道、绑定及播放设置。不保存当前脏地图，不修改其他玩法，不提交/推送。
ArchitectureReviewRequired: false — 建筑局部可复用组件，无旧逻辑退休或框架迁移。风险：组件 Lua 生命周期、组件广播 RPC 在当前引擎需实测；公共建筑需要开启 Actor Replicates。

## TaskStartSnapshot
项目 E:/WeGameApps/rail_apps/OasisEraEditor(2001776)/ShadowTrackerExtra/UGCProjects/EscapeX。
HEAD db83a9927063e5bc92d21c222512d8792859047d。工作树已有多项无关修改；不覆盖。
Run 包修改前 dirty=False，bReplicates=False；ActorSequence/ActorSequence1 的 bAutoPlay=False；Run.lua 为无活动逻辑模板。地图 dirty=True，不由本任务保存。
备份统一存项目根 backup/2026-11-11-as-box-trigger/。

## Baseline read set / evidence
E:/HPYJ/knowledge/gp-docs/README.md、AGENTS.md、manifest.json：2026-10-22 快照，6531/6531，failed=[]。
E:/HPYJ/knowledge/gp-docs/wiki/20312.md:47-63：StartPlay(0,true)。编辑器反射确认 StartPlay 参数 StartTime,bOpenTick。
E:/HPYJ/knowledge/gp-docs/wiki/203.md：属性同步、广播 RPC。
E:/HPYJ/knowledge/recipes/blueprint-asset-scripting-limits.md：SCS 模板读写、变量类型 string、可编辑标志。复杂属性通过 ObjectToolset。
当前 Run.lua、Run 组件树、组件 schema 已检查。无匹配 VFX skill，不涉及特效生成。

## Plan / verification
1. 创建带分组可编辑 SequenceComponentName/Enabled 的 BoxComponent 派生蓝图及脚本。
2. 服务器验证玩家并锁定一次状态；可靠组件 multicast 在各端播放同一 owner 内指定 AS；无兜底序列。
3. 向 Run 加一个组件，开启 owner replication；保留已有序列。
4. 编译保存、回读可编辑配置；Lua 测试重复触发/错误目标/非玩家/副本独立状态；PIE 验证组件生命周期、重叠及同步。无法覆盖的验收明确标记 needs-verification。

Stop: 完整验收才 done；运行验证不足则 needs-verification；权限/用户决策才暂停。