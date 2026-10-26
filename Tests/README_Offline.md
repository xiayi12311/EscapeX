# 离线玩法测试

运行器使用 `.txt` 扩展名，内容是 Python。绿洲编辑器不会把它们当 Lua 执行，也不会反复提示 `.py` 文件不上传。

在项目根目录，用安装了 `lupa.lua51` 的 Python 环境运行：

```powershell
python Tests/run_desk_tests.txt
python Tests/run_capture_tests.txt
```

运行器会检查 Script 下 Lua 文件语法，再执行相应 `.txt` 夹具。脚本按 UTF-8（允许 BOM）读取；不会修改游戏资产。

课桌覆盖状态机、抢占、中断、5/10固定结果、清零/重置、原生点击参数与表现生命周期。抓捕覆盖规则及引擎模拟集成，其中包含“成功抓捕重置全部课桌并清零，失败/重复请求不重置”。

这些测试不等于原生多人、导航、复制和视觉验收；用户实测记录见 Docs/SearchableDesk_PIE验证记录.md。