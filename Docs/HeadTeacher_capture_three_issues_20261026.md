# 抓取实测三项问题修复 — 2026-10-26

## 当前结果

- 已修正 Actor 相对位置接口、测试柱生成高度，补齐囚禁点原生挣脱/解救组件与UI容器引用，替换处罚性质的 Imprisonment 状态。
- 离线规则用例及 **21 组集成测试通过**。新增覆盖客户端显示检查、动作禁用引用计数保留、禁用失败清理、绑柱偏移失败清理。
- PIE `_dkcx30iakizx9t` 客户端 15:29:50.962 明确读到 `text=挣脱 visible=true enabled=true`。用户随后确认“按钮出现，点击后成功脱离”；DS 15:32:46—49记录8次Struggle及 `Released reason=BROKE_FREE`，客户端有 `detached from bind`。**真人原生点击通过**。
- 最终干净启动 `_dkcx30iakj1p3g` 通过：不做临时HandleEnable/UI引用/位置纠正，原生挣脱按钮可见；服务器与客户端绑柱高度误差均小于0.15cm。21组离线测试、真人原生点击、最终干净启动三种证据分别保留，不相互替代。
- 本轮未提交/推送，未修改地图、行为树或课桌资产。分支仍为 `feature/searchable-desk`。

## 1. 位置跳变/掉出世界

确认了两个具体错误，不能只归咎于导航：

1. 旧临时测试驱动以 `pawn.Z - 190` 生成柱子；实测玩家胶囊半高88、中心Z=190.15、地面Z=100、FloorDist=2.1495，旧柱子在Z≈0，低于地面100cm。新驱动 `Tests/capture_pie_driver1.txt` 使用胶囊半高与CurrentFloor.FloorDist推导当前平面地面；临时目录中的旧 `.lua` 驱动不要继续使用。
2. Service/Presentation 对玩家Actor调用了只属于SceneComponent的 `K2_SetRelativeLocation`，且异常被pcall忽略。已改为 `K2_SetActorRelativeLocation`，与 `knowledge/gp-docs/raw/api/c7f9082b0344.json` 核对过；服务器偏移失败会明确释放会话，客户端失败会记录日志并清理挂接。

运行时正确接口实测：DS位置 `(20230.369,28901.189,190.0002)`，客户端 `(20230.400,28901.201,190.0)`；客户端交互重叠恢复true。曾临时测试DisableMovement，但恢复Walking（mode=1）后仍保持Z=190、overlap=true，因此没有把暂停移动模拟写进正式修复。

纠正测试干扰：15:10:56的重新布置探针在玩家已经被自然抓取后又移动了玩家，破坏了现有绑柱相对位置，造成后续overlap=false；该探针不作为产品行为证据。之后已重新挂接并用正确Actor相对位置接口恢复柱位。

## 2. 挣脱按钮

- BP_PrisonPost原先没有ClickActorComponentBase；已加PrisonClick，OverlapCompoent=RescueArea，CheckType=Event，两项原生按钮“挣脱／解救”。
- 回调为CheckBreakFree/OnClickBreakFree、CheckRescuePrisoner/OnClickRescuePrisoner，签名FClick_Param；输入flags=148、bool result输出flags=1073742720，与课桌原生AssignNew签名一致。
- 显示检查在客户端读取同步PrisonState；服务器保留规则校验及执行权限。
- UI配置必须显式指定OuterClass=`/Game/BluePrints/ControlInput/IngameUI/BasicSkillsMenu_BP.BasicSkillsMenu_BP_C`，ButtonClass=`/Game/Arts_PlayerBluePrints/Other/BP_ClickButton.BP_ClickButton_C`，MountWidgetName=`VerticalBox_GISVerticalContainer`。编辑器中课桌的OuterClass读回None，但真实运行时课桌有BasicSkillsMenu，不能直接将编辑器读到的None照抄。
- Python写ClickInfo数组要用具名原生结构体构造器；generic clone的嵌套结构体赋值曾静默回到默认值，已通过保存后读回排除。
- 客户端15:27:30控件数1；15:29:50读回文本“挣脱”、可见且启用。用户此前反馈“仍未出现”发生在上述最终配置及位置纠正之前，最终真人验收尚未收到。

## 3. 禁赛提示

- 抓取不再进入EPawnState.Imprisonment，改用UGCPersistEffectSystem.SetDynamicStateDisabled按动作计数禁用。原始接口依据：`knowledge/gp-docs/raw/api/1947713df52a.json`。
- 禁用行走、冲刺、跳跃、攀爬、持武器、持雷、近战、拾取、切枪、消耗品、开火、瞄准、蹲下、趴下；保留Interacting以供原生挣脱按钮使用。
- 释放只减去本次抓取持有的禁用引用，不重置其他技能的计数。
- 新PIE原生探针确认 `allowMove=false imprisonment=false`，扣除该探针引用后恢复allowMove=true；原生附加动作探针确认开火/瞄准/蹲/趴可被这些Tag禁用。画面中是否仍出现其他提示，等待用户确认；没有增加自定义提示UI。

## 部署及接续边界

- 实际工程已部署并核对源/目标SHA256：CaptureService.lua、CapturePresentation.lua、BP_PrisonPost.lua、Tests/capture_flow_test.txt；原生BP_PrisonPost已保存，副本同步回工作区。
- 当前PIE为最终干净启动 `_dkcx30iakj1p3g`，已经加载最终完整动作清单和Actor偏移修复。早期热重载manager已随旧会话结束而清除。
- 早期会话对运行时PrisonClick做过HandleDisable/HandleEnable/ManualUpdate及UI引用诊断；没有把这些诊断调用写进生产业务流程。最终干净启动未使用这些诊断操作，按钮直接正常创建。
- 运行时怪物HTDamage仍为测试值0；重启PIE恢复资产默认值。正式交付前TRACE仍待关闭。
- 真人点击和最终持久化配置的干净启动已通过。最终探针未见高度跌落，代码不再进入触发禁赛提示的Imprisonment状态；没有宣称所有UI错误提示均已人工逐项验收。多人救援、长期导航测试未在本轮验收。

## 最终干净启动证据

- 15:38:06自然押送到达囚禁点；15:38:07.868绑定，`z=190 postZ=100.0002 move=false fire=false imp=false`，提前挣脱为`NOT_YET`。
- 15:38:22—24共8次服务接口挣脱输入成功（本次自动规则回归，真人按钮验收证据见前一会话）。
- 15:38:24.969服务端：`DONE hits=8 minZ=190 maxBindZError=0.14975 postSession=nil move=true fire=true imp=false invincible=false`。
- 客户端15:38:23.020：`text=挣脱 visible=true`；15:38:23.757：`client detached from bind`。
- 客户端15:38:39.025完成58帧绑柱采样，`minZ=190.14999 maxBindZError=0.14999`。移动模式保持Walking，没有把DisableMovement诊断写进生产代码。
- DS监测及客户端采样定时器均已自行完成。PIE保留运行，测试柱及运行时伤害0仍存在，仅影响本次调试会话。
- 可复用脚本：`Tests/capture_pie_driver1.txt`（正确地面高度布置）、`Tests/capture_clean_retest.txt`（服务端自动规则回归）。不要将离线`.lua`或Python运行器复制到实际工程目录。
- DS日志：`E:/WeGameApps/rail_apps/OasisEraEditor(2001776)/ShadowTrackerExtra/Saved/Logs/EscapeX/DSlog/FullLog/` 中含 `_dkcx30iakj1p3g_realtime` 的文件；客户端日志：`E:/WeGameApps/rail_apps/OasisEraEditor(2001776)/ShadowTrackerExtra/Saved/Logs/EscapeX/Clientlog/FullLog/2026.10.26-15.34.46_client__dkcx30iakj1p3g_1.log`。仅筛 `[HT_CLEAN]` / `[HT_CLEAN_UI]` / `[HTCapture]`，避免完整日志中的凭证。
