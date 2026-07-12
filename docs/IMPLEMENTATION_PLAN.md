# 实现计划

当前阶段完成后停止，不进入真实安装器开发。建议下一阶段按以下顺序推进，每个
阶段都先完成 TestSafe/DryRun、故障注入和回滚测试，再申请 Live 实现授权。

1. **确认外部合同**：核验 Claude Desktop configLibrary schema、固定模型 ID、
   model discovery 开关、Anthropic MSIX 官方 URL/Publisher/包身份、Git 官方签名、
   Cowork 服务与 Windows 前置条件。
2. **纯读取探测**：实现 Windows/Claude Desktop/Git/VMP/硬件虚拟化/Cowork 的
   可注入 read-only providers，不写状态。
3. **Release 安全层**：完善源/staging/ZIP 三阶段 secret 扫描、中文特殊路径解压
   仿真和精确条目比较。
4. **MSIX 和 Git 获取/验签**：先实现下载元数据、缓存、哈希和签名证据；安装仍
   保持关闭。签名失败必须 fail closed。
5. **状态与续跑**：实现 schema 迁移、原子状态写入、重启双重确认、任务所有权和
   失败保留证据，不自动重启。
6. **DeepSeek 凭据与错误分类**：实现 SecureString/credential handle、最短明文
   生命周期、集中错误分类和伪服务合同测试；随后再评审真实 API 验证。
7. **configLibrary 备份/原子写/恢复**：先用 TestDrive 和故障注入证明字节级恢复、
   DPAPI 备份、路径限制与脱敏快照分离。
8. **生命周期与验收**：最后实现 Claude Desktop 显式关闭/启动，以及 Chat、Code、
   Cowork 验收和中文脱敏报告。
9. **Live 安装**：仅在以上证据齐全、用户明确授权后启用；发布前完成独立审计。
