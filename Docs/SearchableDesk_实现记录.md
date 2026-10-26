# 可搜索课桌：实现记录

日期：2026-10-23；引擎：4.18.1-0+++UE4+Release-4.18。

## 当前状态

本轮已尝试原生测试，修复了离线夹具误作运行脚本及双扩展名校验问题。夹具现为 `.txt`，由 Python 运行器读取。最新 PIE 重启在 StartDownload 阶段报 DSFailed（10001），玩法验收仍未通过，详见 [PIE验证记录](SearchableDesk_PIE验证记录.md)。后文“暂不重启”是上一轮实施时的约束，本轮用户已授权启动及重启。

代码及占位资产已在实际工程分支 feature/searchable-desk 接入，三组 Lua 5.1 测试通过；尚未通过原生单人/多人 PIE 玩法验收。

用户确认先用占位抽屉，并要求暂不重启被其他任务使用的 PIE。正式屏幕特效、世界声音、个人语音尚未实现；当前效果为个人文字提示和全体文字广播。

分支起点为 feature/headteacher-ai。已有 DeleteFiles.txt 及并行任务对怪物脚本、地图、缩略图的修改均保留，不归入课桌变更。未保存关卡或摆放永久测试实例，未提交或推送。

## 资产与参数

将 /EscapeX/Asset/Blueprint/Prefabs/Interactables/BP_SearchableDesk 拖入关卡，作为后续 PIE 验证对象。

| 资产 | 内容 |
| --- | --- |
| Asset/Blueprint/Prefabs/Interactables/BP_SearchableDesk.uasset | 课桌蓝图：桌体、独立抽屉、内容物、交互挂点、检测球、搜索按钮 |
| Asset/Models/SchoolDesk/school_desk_SM_SchoolDesk.uasset | 课桌网格 60×40×75cm，原点在底面中心（Blender 源：E:/HPYJ/Art/SchoolDesk） |
| Asset/Models/SchoolDesk/school_desk_SM_SchoolDesk_Drawer.uasset | 抽屉网格 55.6×36.4×15.4cm，与桌体共用地面原点，沿本地 -Y 抽出 18cm |
| Asset/Sequences/LS_DeskOpen.uasset | 0–1 秒抽屉相对位移 0 → -18cm，父绑定 DeskSequenceAuthoring，子绑定 Drawer |
| Asset/UI/WBP_DeskSearchProgress.uasset | 底部居中的搜索文字与进度条（白纹理、左到右填充） |
| Asset/UI/Textures/T_DeskProgressWhite.uasset | 16×16 白色纹理，进度条背景/填充资源 |

课桌和 UI 最终编译状态均为 BS_UpToDate（3），无编译警告；课桌同步距离为30米。创作及探针临时 Actor 已清理。

| 蓝图参数 | 默认值 |
| --- | --- |
| DeskSearchDuration | 3 秒 |
| DeskInteractRadius | 180 厘米 |
| DeskCancelRadius | 220 厘米 |
| DeskOpenDuration | 1 秒 |
| DeskRevealOffset | 0.8 秒，不超过打开时长 |
| DeskOutcomePool | Default |

抽屉与内容物的局部位置/尺寸写在表现模块和 Sequence 中，替换资源时需同步调整。当前姿态：抽屉闭合 (0,0,0)、打开本地 Y=-18；内容物在抽屉内腔（Y 偏移 -0.8，Z=57.6+内容高度一半）。材质：桌面 Wood_Plank、框架 Wood_Log、拉手 Outside_Metal04。纸条为压扁几何体占位，尚无正式贴图或正文；普通/异常物件以不同占位尺寸区分。正式文案仍待替换。

## 文件分工

- Script/Gameplay/Desk/DeskSearchManager.lua：状态机、占用、成功结算、5/10 次覆盖、计数清零、重置和版本检查。
- Script/Gameplay/Desk/DeskOutcomeConfig.lua：权重池、固定纸条、占位尺寸及提示文案/受众。
- Script/Gameplay/Desk/DeskSearchService.lua：真实玩家和距离校验、0.1秒服务器检查、快照发布、延迟反馈和清理。
- Script/Gameplay/Desk/DeskPresentation.lua：进度UI、Sequence、内容物、重置及迟加入状态恢复。
- Script/Blueprint/Prefabs/Interactables/BP_SearchableDesk.lua：蓝图生命周期、整表复制、服务端交互回调、注册和注销。
- Script/Blueprint/UGCGameMode.lua：初始化、清理及公共接口，保留原有怪物/复活逻辑。
- Script/Blueprint/UGCPlayerController.lua：新增断线事件接入，取消该玩家的活跃搜索；实际工程原先不存在此Lua文件。

服务器仅检查活跃搜索；客户端仅在 Searching/Opening 状态启用更新计时器。快照包含 ResetVersion、InteractionId、Revision，旧状态不得覆盖新状态。成功有唯一 OpenEventId，客户端不负责增加计数。

## 公共接口

以下为服务器上的项目自定义接口：

```lua
local gm = UGCGameSystem.GetGameMode()
local count = gm:GetOpenedCount()
gm:ResetOpenedCount()       -- 只清零，进行中的搜索继续
gm:ResetDesk(DeskActor)     -- 指定已注册课桌重置，次数不变
gm:ResetAllDesks()          -- 全部已注册课桌重置，次数不变

-- 同时恢复全部课桌并重新累计：在同一段服务器逻辑中连续调用。
gm:ResetAllDesks()
gm:ResetOpenedCount()
```

失败操作返回 false, reason；GetOpenedCount 在无服务时返回 nil, reason。ResetAllDesks 返回成功标记及失败条目列表。

课桌重置立即清除服务端搜索和占用，客户端收到新状态后停止动画、关闭进度并恢复初始姿态。已经成功的次数不扣回；尚未揭示的延迟反馈取消。重置时重新随机，搜索中断不重抽；第5/10次成功强制覆盖为对应纸条，并替代原随机演出。清零后重新触发第5/10次。

## 验证结果与边界

- 用户实测通过：搜索按钮与读秒、距离中断、第5/10次对应提示、抽屉动画与提示、中文显示、玩家被抓住后所有课桌重置和计数归零。
- 服务器计时与客户端显示统一使用GetServerWorldTimeSeconds；一次原生搜索测得约3.041秒。原生点击回调使用AssignNew的FClick_Param签名；Sequence经类默认对象的静态工厂创建。
- 当前实际工程离线测试通过：三组课桌测试、抓捕规则及22组抓捕集成测试，包含抓捕同时关闭已打开课桌、取消其他玩家读秒、计数归零，以及失败/重复抓捕不重置。
- 测试入口为Tests/run_desk_tests.txt与Tests/run_capture_tests.txt，由Python执行，依赖lupa.lua51。使用.txt避免编辑器对.py不上传的提醒；UTF-8 BOM脚本按utf-8-sig读取。详见Tests/README_Offline.md。
- 多人竞争、迟加入、死亡/断线边界等不能由本轮单人验收代替，仍待原生覆盖。课桌随机物件、纸条、语音等仍有占位资源，详见设计和PIE记录。
- 当前网格使用Wood_Plank、Wood_Log、Outside_Metal04材质，与源Blender预览的纯色材质不同；已检查并向用户说明，未擅自改回。正式视觉需后续确定。
- 详细原生证据、用户验收与历史排错过程见SearchableDesk_PIE验证记录.md。
## 依据

本地官方快照为2026-10-22。以下路径均相对工作区：

- knowledge/gp-docs/wiki/203.md：整表复制、OnRep及RPC。
- knowledge/gp-docs/wiki/20427.md：ClickActorComponent及执行端。
- knowledge/gp-docs/raw/api/b10c5fce63d3.json：GameMode、服务器时间及玩家查询。
- knowledge/gp-docs/raw/api/f071c6cf5008.json：计时器创建/移除。
- knowledge/gp-docs/raw/api/1f6564347ba0.json、69c69da89877.json：存活/退出与断线事件，未以IsExit替代断线。
- knowledge/gp-docs/raw/api/af42f5a60459.json、469e9226abe8.json、b47a5165923e.json：Sequence创建/绑定/播放。
- knowledge/gp-docs/raw/api/3afee7c0e0a1.json、1348ded84123.json、e30a54bd48af.json、77a1929f7b26.json：UI创建/查找/进度与文字更新。

编辑器自动化补充参考：[序列实现](https://github.com/20tab/UnrealEnginePython/blob/master/Source/UnrealEnginePython/Private/UObject/UEPySequencer.cpp)、[节点实现](https://github.com/20tab/UnrealEnginePython/blob/master/Source/UnrealEnginePython/Private/Blueprint/UEPyEdGraph.cpp)，以当前编辑器实际查询接口为准。
