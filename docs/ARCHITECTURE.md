# Architecture

```text
six .cmd launchers
        |
   Start-Here.ps1
        |
   lib/bootstrap.ps1
        |
 common -> installer -> configuration -> workflow
```

- `common.ps1`：结果、运行时验证、产品路径、ACL、临时目录和安全异常。
- `installer.ps1`：可信 Git 检测/安装、bounded download、签名、MSIX identity、
  Claude per-user 安装。
- `configuration.ps1`：8 个 policy 值、helper 编译、DPAPI、ownership、诊断和恢复。
- `workflow.ps1`：Install / Diagnose / Restore 顺序与用户结果。

入口默认 DryRun；双击 wrapper 显式选择 Live。bootstrap 顶层只定义/加载函数，不做
网络、系统探测或写入。

Clean VM snapshot 是测试环境的外部前置，不是用户产品运行时条件。仓库不再包含
provider graph、access ledger、stage reducer、receipt binding 或 operator plane。
