# 班主任客户端绑柱解挂复测 — 2026-10-26

## 结论

SessionId 修复部署后，真实 PIE 客户端已出现 `client detached from bind`，交接中的客户端解挂缺口闭合。本轮验证不代表押送导航、真人交互按钮或多人救援已验收。

## 环境与部署

- PIE DebugID：`_dkcx30iakiy1ny`，DS + 单客户端。
- 仅部署 `Script/Gameplay/Capture/CaptureService.lua`、`Tests/capture_flow_test.txt`；源与目标逐文件 SHA256 一致。
- Service SHA256：`926B38F62F5229F136419B13B2A66450866E040D0C3052F7EAFBAA4D10E07436`。
- Test SHA256：`F2AF77A7CA5360846A1C223F986C15D77D6354DAA15E0069BFEA6B70956894C6`。
- 未修改地图、蓝图或行为树资产；未提交或推送。

## 实测证据

1. 旧 driver1/driver2：两根运行时柱子自行注册，整表复制到客户端，Revision=99、无 SessionId 探针完整读回；两份驱动均 `failures=0`。
2. session 1、2 自然抓取成功，客户端 carry attach/detach 成功，但押送均 `ESCORT_TIMEOUT`，未绑柱。
3. session 3 将运行时测试柱放在怪物附近，仍由原 BTT 阶段机自然抓取和报告到达；`capture_arrive ... gap=120 ok=true`，未手工调用 MarkArrived。
4. DS 14:39:55.507：`BOUND session=3 payloadSession=3 rev=14`；随即 `early=false reason=NOT_YET`。
5. 首次成功挣脱输入距检测绑柱约 15.230 秒；8 次输入均成功，间隔约 0.267 秒（通过 Service.Struggle 发起，未经过真人 UI）。
6. DS 14:40:12.875：`DONE hits=8 frozen=false invincible=false postSession=nil state=Free session=3`。
7. 客户端 14:39:54.391：`[HTCapture] client attached local pawn to bind`。
8. 客户端 14:40:11.617：`[HTCapture] client detached from bind`。

客户端与 DS 日志时间存在差异，跨端时间戳不用于计算阶段时长。以上结果证明客户端在已有 revision 高水位后接受 SessionId=3 的绑柱及 Free 状态。

## 日志位置

- DS：`E:/WeGameApps/rail_apps/OasisEraEditor(2001776)/ShadowTrackerExtra/Saved/Logs/EscapeX/DSlog/FullLog/2026.10.26-14.31.02_ds__dkcx30iakiy1ny_realtime.log`
- 客户端：`E:/WeGameApps/rail_apps/OasisEraEditor(2001776)/ShadowTrackerExtra/Saved/Logs/EscapeX/Clientlog/FullLog/2026.10.26-14.30.41_client__dkcx30iakiy1ny_1.log`
- 仅按 `[HT_RETEST3]`、`[HT_RETEST5]`、`[HT_RETEST6]`、`[HTCapture]` 筛选；完整日志可能包含凭证，不整段复制。

## 剩余问题与运行状态

- 前两次押送分别在较远测试柱和缩近后的测试柱处超时，根因尚未诊断。最后一次使用近距离测试场景，因此不能据此宣布押送导航通过。
- 交互按钮未配置，真人挣脱/救援 UI、多人救援未测；本轮没有增加输入通道或兜底逻辑。
- PIE 保持运行。三个验证定时器均已自行结束，session 3 已释放；两根测试柱仍在运行时世界中，`BP_PrisonPost_C_0` 已移动到测试位置。
- 本轮把该只怪物运行时 `HTDamage` 设为 0，未改资产，重启 PIE 后重置。诊断 TRACE 仍为原有开启状态，正式交付前待关闭。
