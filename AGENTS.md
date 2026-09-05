# FernDrop 开发约定

先读 README.md 和 docs/ 下协议/存储/设计/执行文档。项目只针对个人 Mac + Windows；Android 不在当前范围。

共享 ui/ 是唯一界面实现，保留浅色、10 个像素角色状态（每个5帧）及 reduced-motion。不以假记录、假在线状态或假进度替代真实功能。

协议 v1：AES-GCM nonce12+ciphertext+tag16；重试使用同一密文；云端 seq 永不回退。20MB 阈值、200MB 云端总额、72h 云端保留、普通本地目录30天、大文件不自动删除。

删除逻辑必须覆盖路径越界、符号链接/junction、占用和活跃任务保护测试。禁止对真实工作目录执行破坏性测试。

Windows 执行方只在 windows/ 和 docs/WINDOWS-RESULTS.md 实施平台适配；必须的共享修复可单独提交并解释兼容性。不要重选框架或重做设计。

使用 Git 独立分支。不得提交服务器密码、实际令牌、空间密钥、配对导出或用户传输文件。只允许标明用途的测试固定密钥进入测试样例。

验证：npm test；Mac bash scripts/build-mac.sh，随后 --self-test、node tests/native-integration.mjs、node tests/sendme-integration.mjs。Windows 依据 WINDOWS-HANDOFF.md 执行。
