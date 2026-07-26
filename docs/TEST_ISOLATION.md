# Test isolation

## 宿主机与 CI

只允许运行 parser、Pester、静态 inventory、helper 临时编译和 Release DryRun。不得调用
Install Live，不得访问真实 Claude/Git 配置、注册表 policy、AppX、凭据、进程或产品
下载。测试写入只使用 Pester `TestDrive:`。

`Start-Here.ps1` 未显式 `-Live` 时只返回计划，且不执行网络、进程、注册表、AppX 或
产品文件写入。

## Disposable VM

只有 VM 允许用户确认后的 Live：

- 安装官方签名 Git；
- 安装官方 Claude MSIX；
- 关闭/启动 Claude；
- 写项目 HKCU policy 与 DPAPI credential；
- 用户在遮罩提示中本地输入 Key。

Key 不进入 Codex 对话、命令行、环境变量、截图或测试报告。VM snapshot 的恢复由外部
操作者完成；产品不验证 snapshot receipt。

VM 只回传安全错误码、步骤和无敏感信息的现象。任何候选字节变化后重新构建再测。
