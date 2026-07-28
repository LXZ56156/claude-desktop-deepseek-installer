# Contributing

先复现一个真实 Windows 11 VM 故障，再增加对应的最小实现和回归。不要为假设中的未来
场景新增 provider framework、receipt schema、snapshot authorization、worker/shard
或第二套质量门。

提交前在 64 位 Windows PowerShell 5.1 运行：

```powershell
.\scripts\check.ps1
.\scripts\build-release.ps1 -DryRun
git diff --check
```

不得在 issue、fixture、测试、日志或提交中放入真实 API Key。Live 安装只在 disposable
VM 中执行，用户只在本地遮罩提示输入 Key。

新增、删除或重命名文件时同步更新 `scripts/release-manifest.psd1`。用户包只能包含
`PackageFiles`。
