# Testing

唯一阻塞命令：

```powershell
.\scripts\check.ps1
```

它在一个 64 位 Windows PowerShell 5.1 进程内完成：

1. 验证固定 Pester 5.6.1 tree。
2. 用 PS5.1 parser 检查产品与质量脚本。
3. 一次 `Invoke-Pester` 运行两个 focused 文件。
4. `scripts/build-release.ps1 -DryRun`。
5. `git diff --check`。

`tests/Practical.Tests.ps1` 守住入口 DryRun、官方 metadata/parser、签名发布者、hash
顺序、bounded download、MSIX identity、8 个 policy 值、helper 编译和 Key 边界。

`tests/Release.Tests.ps1` 守住 22 文件精确白名单、完整分类、编码、已退役路径不存在和
单一质量门。

测试不模拟数百种未来故障。Git/Claude/Chat 的成功标准由 disposable VM 真实运行，
失败后才加入窄回归。
