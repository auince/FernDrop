# 给 Windows Codex 的执行单

## 任务与约束

你是 FernDrop 的 Windows 执行方。Mac 侧已完成产品/视觉/协议设计。首先阅读 README.md、AGENTS.md、PROTOCOL.md、STORAGE.md、DESIGN-SYSTEM.md 和 VALIDATION.md，随后按此清单实现 Windows 原生外壳并在本机编译验收。不要重新选择跨平台框架，不重新设计界面，不生成另一套角色素材，不改服务器 wire format。

本次仓库交付 **没有假装存在已完成的 Windows 应用**。windows/ 提供协议参考实现和校验程序；以下原生适配是你的明确实施任务。用户所说“只负责执行”指按既定规格实现、编译、测试，无需重新向用户开展产品设计访谈。

当前目标机器：Windows 11 家庭版 x64，约 32GB RAM，已有 VS 2022 Build Tools/C++、Git、Node。没有确认 .NET SDK。不要配置 RDP 服务端（家庭版不支持），不要求 SSH。

## 固定技术选型

- .NET 8，WPF，STA 桌面进程。
- Microsoft.Web.WebView2：加载仓库 ui/。使用虚拟本地域 `https://ferndrop.local` 映射静态资源，阻止导航到其他源；仅信任该主框架的 WebMessageReceived。
- 系统 IO、HttpClient、System.Text.Json、AesGcm。
- Clipboard：WPF DataObject/Clipboard，图片 BitmapSource，文件 FileDropList；若 WPF 无法稳定监听，使用 AddClipboardFormatListener + WM_CLIPBOARDUPDATE。
- LAN：使用 Windows DNS-SD API 或固定开源 mDNS 库，广播 `_ferndrop._tcp`；TCP 按 PROTOCOL.md。先完成云端与剪贴板闭环，再接入 LAN；禁止用假 LAN 成功代替实测。
- sendme v0.36.0 Windows x64 子进程，参数通过 ArgumentList，不拼接 shell 字符串。

## 先执行的环境核查

```powershell
git --version
node --version
dotnet --list-sdks
```

如果无 .NET 8 SDK，使用微软官方安装方式，安装后再继续。已安装 C++ 工具不等于已安装 .NET。

在 D:\Projects\FernDrop 打开项目，勿放在会自动清理的接收目录。先运行 `npm test`；然后运行 `dotnet run --project windows/ProtocolCheck.csproj -- windows/crypto-fixture.json` 校验 AES-GCM。

## 文件实施清单

在 windows/Desktop/ 下创建 FernDrop.Windows.csproj（net8.0-windows、UseWPF）、App.xaml、MainWindow、NativeBridge、ClipboardService、FileStore、RelayClient、LanTransport、SendmeService、CredentialStore。共享 UI 通过构建 Copy 链接 ../../ui/**，不可复制后另行维护分叉。

### 1. 主窗口和桥接

默认 1130×850，最低 880×720，浅色背景；托盘常驻，关闭隐藏、退出终止进程。前端已支持 `window.chrome.webview` 消息，直接匹配 PROTOCOL.md 全部 method。bootstrap 返回 platform:"Windows"。不要把 Mac 的路径/名称硬编码到 Windows。

所有 Reply 都有 request id；捕获异常后给用户可读错误，不让 UI 挂起。UI 线程负责 Clipboard、文件提交和状态变更；耗时 IO 在后台执行并返回 Dispatcher 提交。

### 2. 本地文件与安全存储

默认根目录 D:\文件传输（不存在 D 盘时用户 Downloads/FernDrop）。完整复现日期目录、标记、无覆盖重命名、30 天保护清理、大文件排除；Windows 处理保留文件名、junction/reparse point，禁止清理穿透到目录外。

Settings/History 放 LocalApplicationData/FernDrop；空间密钥和 token 用 CurrentUser DPAPI，不明文写普通配置。使用 windows/Protocol.cs 的加解密布局。

### 3. 剪贴板

监听 text/image/file list。接收端必须实际 SetFileDropList，使用户能在资源管理器 Ctrl+V；不要仅复制文件路径文本。复制图片应使画图/WPS/聊天输入能粘贴图片。写入自定义格式 app.ferndrop.remote 并记录 GetClipboardSequenceNumber，禁止回环。处理剪贴板暂时被占用时的有限退避。

复制操作失败不影响已接收文件保存。自动覆盖规则同 Mac：只处理小于 15 秒的新事件，不覆盖本地未观察的复制；补收不覆盖。图片和文件任务完成前不写不完整数据。

### 4. 传输与恢复

小文件加密后持久化 outbox，同一 id 重试原始密文；20 秒重试等待任务，2 秒轮询事件。成功写入 history/seen 才推进 cursor。HTTP 使用 HTTPS，本机回环允许 HTTP。507 不丢文件、不清掉未过期云端内容。

sendme 通过 `send PATH --relay disabled --no-progress` 和 `receive TICKET --relay disabled --no-progress` 调用。勾选允许中继才用 default。任务目录单独隔离，输出提取 blob 票据，可手动复制也可加密自动交换。stdout/stderr 是流，按增量缓冲提取，退出码/文件完整性判断成功。不要把进程启动等同传输完成。实际路由遥测不足时显示“仅直连/允许中继”策略，不伪造直连状态。

### 5. 原生界面交互

实现添加文件、拖入<=20MB文件、打开文件夹、复制、重试、设置保存、导入导出配对、清理、sendme停止。保留 shared UI 的键盘事件，将页面里的平台提示根据 snapshot.platform 做适配；Windows 用 Ctrl。

## 验收顺序（必须记录证据）

1. 协议固定向量解密成功，篡改 tag 必须失败。
2. Windows 本机 text/image/file 三类写入与粘贴验证。
3. 自己向 relay 上传、下载、去重，服务重启后游标继续。
4. Mac 与 Windows 互相复制 Unicode 文本、截图、1–2MB 文档、19MB文件、多文件，路径正确。
5. 断网、应用重启、相同名字重复接收，不能重复记录或覆盖原文件。
6. 同一 LAN 验证流量不经正文云端；关闭 LAN 可达性后小文件正常回退云端。
7. 25MB/100MB sendme，两端在线，直连和失败状态真实；中继开关明确。
8. 清理用专用测试根目录和合成旧日期；不拿用户真实工作文件试删。
9. Windows 100/125/150% DPI、动画关闭和 reduced-motion、中文路径与输入。

把结果写到 docs/WINDOWS-RESULTS.md，记录 commit、构建命令、用例、实际结果、未完成项。对跨端协议的必要修复通过单独提交说明；禁止仅修改一端格式后宣称完成。

## 交接方式

独立 Windows 分支，通过 Git 提交交换；Mac 侧负责总集成。没有任务通信桥时用户转发阶段结论。仓库凭据、阿里云密码、配对配置均不得写入代码或提交。

## 配对校验修正

允许serverURL/token同时为空的仅局域网配对（spaceKey仍需32字节）。云端地址非空才要求至少24字符的token；不完整JSON提供格式提示。对照mac/Core.swift的PairingConfiguration及PROTOCOL.md实现，禁止用“配置不完整”一概拒绝LAN配置。
