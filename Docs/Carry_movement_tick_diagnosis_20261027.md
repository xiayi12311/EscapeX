# 2026-10-27 搬运滑移诊断与修复

## 范围

处理被抓玩家自己的视角在搬运期间抖动/滑移，以及已授权的怪物穿过玩家。未改课桌、地图或怪物资产；未提交 Git。接续 `.handoff/20261027T014158Z-carry-drift-movement-lock-unmeasured.md`。

## 已量化的问题

1. 实际玩家胶囊碰撞对象通道为 2（ECC_Pawn），旧实现忽略 16 和 4，但 4 是 ECC_Camera。将怪物 Capsule/HitBox 忽略通道改为 2 和 16，两端 BeginPlay 执行；新会话读回实际玩家通道 response=0。修正前曾出现异常快速搬运，修正后实际押送速度恢复约 300 cm/s。
2. 两端 `MovementMode=0` 仍不能阻止相对位置滑移。正常押送速度下，约 8 秒相对漂移仍有约 7 米。
3. 在相同会话中只新增“搬运期间暂停两端 CharacterMovement Tick”这一变量后，滑移降到数值精度范围。底层具体是哪条 C++ 更新/网络修正路径尚未定位，不将此推断写成事实。

| 会话 / 实验 | DS 相对坐标范围 XYZ，cm | 本地客户端范围 XYZ，cm | 备注 |
| --- | --- | --- | --- |
| `_dkcx30j651k2yw` / `[CARRY_CHANNEL_*]` | 695.6739, 66.5308, 0（80点） | 697.9518, 68.8808, 0（80点） | Pawn 通道修正，Mode=None，Tick 仍开启 |
| 同会话 / `[CARRY_TICK_MEASURE_*]` | 0, 0, 0（70点） | 0.0024, 0.0013, 0（69点） | 仅新增暂停 Tick，老师移动约20米 |
| 同会话 / `[CARRY_FIX_*]` | 600.2843, 208.4988, 0 | 600.2786, 208.4999, 0 | 保存后 reloadlua 未真正换新嵌套模块；两端读回 tick=true，不能作新代码验收 |

采样每0.1秒，范围忽略头3点，进入 PuttingDown 后结束。第一轮 `_dkcx30j651jf7i` 中老师异常移动169米/8秒，属于混杂条件，不能用它宣称 None 已解决服务器漂移。

## 保存的实现

- `HTCommon.lua`：忽略实际 Pawn 2 与 PlayerPawn 16，保留 Camera 原响应。
- `CaptureService.lua`：搬运附着前，记录原 Tick 状态、设 None 并暂停 CharacterMovement Tick；绑定期间持续暂停；Released 解挂后设 Walking，再恢复原 Tick 状态；附着失败走同一恢复。重复持有不会覆盖原始快照。
- `CapturePresentation.lua`：本地 Pawn 挂接后做同样暂停，退出时恢复；保存被持有的 Pawn，避免旧抓捕结束时误改已经重生的新 Pawn。
- 不使用每帧设位置、瞬移跟随或反复重挂来压住漂移。测试触发抓捕时的一次性临时定位只存在于控制台，没有写入生产逻辑或地图。

## 验证与边界

- Lua 5.1 语法和捕获规则测试通过；28组抓捕集成测试通过，24组班主任测试通过。
- 恢复覆盖：死亡/离场、中止、怪物销毁、服务关闭、移除囚禁点、搬运/绑定附着失败、本地结束、原本 Tick 关闭、重生替换 Pawn。
- 上述退出路径多数为离线引擎适配层测试，不能代替每种原生场景验收。
- 保存后的完整初始化会话：`_dkcx30j651ktxt`。用户实测反馈“都成功”，确认搬运镜头及释放后行走通过。该轮探针尚未取得可用的搬运窗口，不能将上表单变量实验数值冒充本轮测量。
- `K2_AttachToActor` 仍挂怪物根胶囊，`headSocket` 只是记录的插槽名，当前没有切换 Mesh 父组件。这是独立的肩部定位问题，不能与 Tick 实验混改。

## 已记录但暂不处理：玩家与怪物重合，相机过近

用户在本次复测后明确要求“先记录不处理”。表现为玩家位置与怪物完全重合，自己的相机特别近。已知实际父组件是怪物根胶囊，玩家相对位置趋近零；应在后续独立任务中验证 Mesh 插槽及搬运偏移与镜头构图。本轮保持现状，未调整挂接组件、偏移或相机。

## 复核入口

- DS：`Saved/Logs/EscapeX/DSlog/FullLog/2026.10.27-10.07.00_ds__dkcx30j651k2yw_realtime.log`
- 客户端：`Saved/Logs/EscapeX/Clientlog/LuaLog/2026.10.27-10.06.30_client__dkcx30j651k2yw_1.log`
- 仅过滤上述标签，日志包含敏感信息，不整段导出。
- 知识库依据：`E:/HPYJ/knowledge/gp-docs/raw/api/009c32ccfe01.json`（SetComponentTickEnabled、IsComponentTickEnabled）、`a9add0efb9bb.json`（SetMovementMode）。碰撞枚举经编辑器反射及真实 Pawn 读回。
