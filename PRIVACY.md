# Privacy

安装器不收集遥测，不上传日志，也不创建包含用户输入的报告。

它会访问以下公开服务：

- GitHub API 与 Git for Windows release 下载，用于缺失/损坏 Git 的安装。
- Anthropic 官方 Claude Desktop endpoint 与下载域名，用于取得最新 x64 MSIX。

DeepSeek API Key 只在本机遮罩输入一次。安装器将它转换为 DPAPI CurrentUser 密文，
并清零可清零的临时字符/字节缓冲区。Key 不进入参数、环境变量、日志、状态或注册表。
Claude 运行时通过无参数 credential helper 的 stdout 读取 token，随后按第三方推理
配置把请求发送到 `https://api.deepseek.com/anthropic`。

Anthropic 文档说明 Claude 自身在 Code/Cowork 运行期间可能创建 owner-only 临时凭据
文件；这属于 Claude 的运行时行为，不是安装器的持久化副本。

恢复入口只删除本项目拥有的 policy、helper、DPAPI 密文和状态，不删除 Git、Claude
或用户的其他 Claude 数据。
