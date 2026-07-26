# VM acceptance plan

## 第一轮：唯一阻塞 happy path

从 clean Windows 11 x64 disposable VM 开始，确认没有本项目状态；优先选择无 Git、
无 Claude 的快照。

1. 取得同一 PR head 构建的 ZIP 和 SHA-256。
2. 完整解压；不要从 ZIP 内直接运行。
3. 双击 `开始安装.cmd`，阅读提示并确认。
4. 若出现 Git UAC，确认 signer/来源后允许。
5. 用户在遮罩输入框本地输入 Key；Codex 不读取、不截图、不转述。
6. 验证 Claude 被安装并打开。
7. 在 Chat 发送最小文本消息，确认真实 DeepSeek 响应。
8. 双击诊断，要求 `SUCCEEDED`。
9. 再次安装，验证复用和幂等。
10. 运行恢复，再安装一次，验证可恢复性。

第一轮只要 Git、Claude、Key/config、真实 Chat、rerun、restore 成功，即标记
`PRACTICAL_VM_HAPPY_PATH_PASS`。Code 可记录观察；Cowork 不阻塞。

## 后续轮次

只根据第一轮可复现失败增加测试：

- 代理/DNS/官方 endpoint；
- Git UAC 或安装退出码；
- AppX/AppLocker/package conflict；
- 企业 HKLM/HKCU policy；
- helper 编译/ACL/DPAPI；
- 重复运行或恢复。

报告只含安全错误码、阶段、Windows build 和无敏感现象。不得回传 Key、credential、
registry export、个人配置、完整日志或截图中的输入。
