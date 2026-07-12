# 测试与质量门

## 本地依赖

```powershell
pwsh -NoProfile -File .\scripts\bootstrap-dev.ps1
```

脚本固定 Pester 5.6.1，并只保存到被 Git 忽略的 `.dev/modules`。它不执行
`Install-Module`，不修改全局或 CurrentUser 模块配置，也不持久修改
`PSModulePath`。

## 完整检查

```powershell
pwsh -NoProfile -File .\scripts\check.ps1
pwsh -NoProfile -File .\scripts\build-release.ps1 -DryRun
git diff --check
```

检查内容：

- PowerShell AST 语法；
- PowerShell 7 和 Windows PowerShell 5.1 无副作用模块加载；
- 公开函数合同；
- `config/public-functions.psd1` 对每个库文件的精确函数集合、Mandatory 参数和
  `Mode=TestSafe|DryRun|Live` 合同；
- Pester Unit/Contract；
- 默认 JSON 配置结构；
- `.cmd` ASCII/no-BOM 与 `.ps1/.psd1` UTF-8 BOM；
- 敏感信息扫描；
- 当前脚手架禁止命令 AST；
- Release manifest 对全部仓库文件的精确分类；
- Release DryRun 的源扫描和白名单验证。

## 未来测试原则

- 真实系统能力通过 provider 注入，Unit 不访问真实系统。
- 文件写入只使用 `TestDrive:` 或唯一临时目录。
- 故障注入覆盖下载中断、签名错误、原子替换失败、备份失败、API 超时、重启
  checkpoint 损坏和验收失败。
- ZIP 用户仿真必须解压到包含中文、空格和 `&` 的路径，并只运行 TestSafe。
- 任何 Live 路径都需要独立确认和外部环境验收，不能由 CI 自动触发。
