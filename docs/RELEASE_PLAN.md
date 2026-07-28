# Release plan

`scripts/release-manifest.psd1` 是唯一 inventory 事实来源。当前 ZIP 精确包含 22 个
用户文件；测试、scripts、docs、Pester、Git metadata、日志和证据都不进入包。

```powershell
.\scripts\check.ps1
.\scripts\build-release.ps1 -DryRun
.\scripts\build-release.ps1
```

实际构建使用 owner-marked 随机临时目录，逐文件复制白名单，比较 staging 与 ZIP
inventory，并输出 ZIP SHA-256。已有同名输出时停止，不覆盖。

当前阶段只允许 development ZIP 进入 disposable VM。不得自动 merge、创建 GitHub
Release、promotion 或宣称 general release ready。至少需要 `PRACTICAL_VM_HAPPY_PATH_PASS`
和用户确认。
