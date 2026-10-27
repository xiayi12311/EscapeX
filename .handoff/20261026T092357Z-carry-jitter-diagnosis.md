## User checkpoint

2026-10-26原生用量工具确认五小时已用94%，剩余6%，触发用户停止规则。当前任务是检查“玩家被抓住搬运时自己画面/镜头抖动”的原因；未改任何游戏代码，未实施修复。

已量化：PIE_dkcx30iakj7xl9的一轮自然搬运，双端各50次0.1秒采样，忽略最初3点后玩家RootComponent.RelativeLocation的X/Y波动：DS451.872/76.870cm，客户端450.871/79.721cm；Z波动均0。两端MovementMode=1（Walking）、GravityScale=1、CollisionEnabled=1，velZ=0。不是仅凭感觉判断：附着后的相对位姿确实不稳定，但“Walking/网络纠正导致”仍是候选原因，未做隔离A/B，不能声称根因已证实。

一个3分钟只读父组件探针已启动，最后查日志无输出，当前状态未知；PIE仍保留运行，没有声称暂停。下次需用户明确继续且额度允许。

## Task contract

用户要求检查抖动原因，明确复现视角是“被抓玩家自己的画面/镜头”，两次确认不操作移动键仍抖动。范围为抓捕搬运附着、移动模拟、网络位置同步与镜头挂点诊断。不得借本记录擅改怪物/课桌玩法，不添加瞬移、每帧钉位置等兜底；AGENTS规定任何兜底须用户确认。

此前课桌/抓捕重置已验收并提交：57f2e9c课桌和抓捕联动，1f3d1cd地图导航资产整理；旧headteacher功能分支已安全删除，历史保留于feature/searchable-desk。不要重复做这些工作。

## Next action and boundary

前提：用户明确继续，重读项目指令并检查额度。一个原子下一动作：只读最新客户端日志中[CARRY_PARENT_QA]，报告父组件、插槽与角色Movement.UpdatedComponent是否一致；没有结果则明确缺口，不擅自启动第二套探针或修改角色模拟。

其后若继续诊断，需要区分角色移动组件/客户端纠正与挂点/载体运动，不能把多项DisableMovement/关碰撞/关平滑同时开关后称为定位。

## Delivery and acceptance ledger

|Item|State|Evidence|User review|
|---|---|---|---|
|抖动复现|verified|用户确认自己的镜头抖，两次搬运复现|后续修复同场景复测|
|双端位姿采样|verified|17:21:32—38，[CARRY_JITTER_V2]各50点|无需再次口述复现|
|实际附着父组件/插槽|in progress|只读CarryParentQA.timer已安装，检查点前无输出|必要时再搬运一次|
|根因隔离与修复|not started|无A/B数据，无代码修改|等待继续授权|

进程快照：2026-10-26 09:23:57 UTC检查。PIE最近ctx为运行中，DebugID_dkcx30iakj7xl9。V1探针已自行结束，n=0（窗口未覆盖搬运，不可当反证）；V2两端已完成50点并移除定时器。CarryParentQA仅客户端：每0.1秒等待Carrying且PlayerKey为本地玩家，读RootComponent.AttachParent、AttachSocketName、CharacterMovement.UpdatedComponent和预期怪物Mesh，成功即打印[CARRY_PARENT_QA]并移除，最多1800tick/3分钟。最后日志无输出；此后状态未知，勿从本记录推断仍活着，也不要并发重复安装。不停止PIE、不杀任务。

## Minimal reading package

### L1: next-action sources

1. Saved/Logs/EscapeX/Clientlog/FullLog/2026.10.26-17.08.44_client__dkcx30iakj7xl9_1.log（本地日志，可能不可携）：继续授权后仅筛[CARRY_PARENT_QA]和[CARRY_JITTER_V2]；原生运行时证据，2026-10-26。
2. 同日志根DSlog/FullLog/2026.10.26-17.09.16_ds__dkcx30iakj7xl9_realtime.log（本地）：需对照服务器搬运样本才读；仅筛调试标签，原生权威位置记录。
3. Script/Gameplay/Capture/CapturePresentation.lua与CaptureService.lua：明确下一步分析附着实现时读；当前HEAD生产代码，未被本次诊断修改。

### L2: read conditionally

1. E:/HPYJ/knowledge/recipes/player-attach-and-state-probes.md：需要历史双端Attach边界时读；旧实测表明server-only Attach不带动owning client，故当前两端Attach。
2. Docs/HeadTeacher_capture_three_issues_20261026.md：若考虑DisableMovement/绑柱高度时读；之前绑柱稳定不代表搬运稳定。
3. Script/AI/HeadTeacher/HTCapture.lua与HTCommon.lua：判断怪物Escort移动节奏时读；不得改动未验证相关的导航策略。
4. E:/HPYJ/knowledge/gp-docs/raw/api/a9add0efb9bb.json：准备移动模式隔离实验时核对API；Walking继续处理地面移动，NetworkSmoothingMode文档针对simulated proxies，不可直接推断owning client。

## Decision/risk notes

- blocking：原生双端附着相对X漂移约4.5m而Z稳定，根因尚未隔离。不能直接说重力导致抖动；样本velZ=0。
- blocking：CaptureService.attach与Presentation.grab都校验actor.Mesh的socket，却调用pawn:K2_AttachToActor(actor,socket,2,2,2,false)，未明确指定Mesh。需看父组件探针再判断是否挂错组件，不能从函数名推断。
- 候选：抓住只用SetDynamicStateDisabled禁用操作，没有停止CharacterMovement模拟；样本仍Walking/Gravity1/Query碰撞。禁用输入不等于停止移动模拟，尚无A/B证实其因果。
- 候选：客户端headSocket相对怪物Z波动61.840cm，DS波动0；但玩家相对怪物Z波动均0，不能说头部上下摆动已直接驱动了这次玩家镜头。需看真实附着对象与世界位姿。
- 日志可能含凭据，只输出上述标签，不能整段dump。

## Scope escalation

blocking：仅搬运抖动诊断与后续经授权的最小修复。已知课桌材质与原图不同、多人救援等另有记录，均不扩入本次。没有全局暂停其他会话的授权。

## Trace metadata

主仓库E:/WeGameApps/rail_apps/OasisEraEditor(2001776)/ShadowTrackerExtra/UGCProjects/EscapeX；工作副本E:/HPYJ/EscapeX非Git仓库。分支feature/searchable-desk，HEAD1f3d1cde5b84b18558f467ec63701175bdface82；main7dd4676未动。最后git status仅DeleteFiles.txt、Thumbnail.png、UGCmap.umap修改，来自本次诊断外，勿还原。新手记另为未跟踪文档。

本轮没有提交、推送、生产代码编辑或移动参数修改。工作区AGENTS与用户低额度规则适用，真实工程文件写入需正常sandbox escalation。原生用量read-only工具94%后仅做检查点保存。

## Continuation contract

新会话先读项目指令和本记录L0，报告有限对齐和缺口，等待用户明确继续授权，不自动读取L1/L2。本记录不独立授权测试、实现、重启、提交或推送。用户选择新会话并可用$handoff-continue指定此路径。