# FernDrop 架构与功能边界

版本：0.1.0 / 2026-09-05。目标是个人 Mac + Windows 文本、图片、普通文件传输。Android 不在当前范围。

## 已确定的实现

Mac：Swift + AppKit + WKWebView，最低 macOS 13，源码不依赖 Swift 包；共享界面为无构建步骤的 HTML/CSS/JavaScript。服务端：Node.js 22 内置 HTTP/文件系统，无 npm 运行依赖；单进程、单个人空间。大文件：独立 sendme v0.36.0 进程。Windows：按 WINDOWS-HANDOFF.md 实现 .NET 8 WPF + WebView2 平台外壳，原样复用 ui/ 与协议，不重设计界面或数据格式。

代码关系：

- ui/index.html：三个主入口、大文件子页及可访问控件。
- ui/styles.css：唯一视觉规范实现、响应式与 reduced-motion。
- ui/app.js：状态渲染、筛选、搜索、原生桥接；不直接访问网络，不保存文件、不拥有密钥。
- mac/Core.swift：数据模型、文件目录、重名、清理、CryptoKit AES-GCM、钥匙串。
- mac/App.swift：原生应用生命周期、剪贴板监听、发送队列、云端客户端、接收、sendme 调度、WebKit 桥接。
- mac/LAN.swift：Bonjour 发现、TCP 帧、空间密钥认证和加密 ACK。
- server/server.mjs：授权、加密数据暂存、事件游标、配额和过期。

## 路由

普通内容总字节数 <=20,000,000：将 envelope 加密并保存 outbox → 尝试 Bonjour 发现的局域网候选 → 验证加密 ACK → 失败后 PUT 云端。成功直传不上传文件正文到云端。多文件以整批合计判断阈值；文本单条限制 1,000,000 UTF-8 字节。

大于阈值，或用户在大文件页手动选择：本地大文件目录保留发送副本 → 启动 sendme → 提取票据 → 票据作为加密 envelope 按同样的 LAN/云端路线通知另一端 → 另一端启动接收进程 → 校验成功后移入大文件目录。文件正文不进暂存服务器。也可手动复制/输入票据。

默认 --relay disabled；用户勾选中继后两端使用 --relay default。UI 显示配置策略（仅直连/允许中继），目前未提供实际链路类型遥测，不能把“允许中继”标成“公网直连成功”。禁用中继可能降低复杂 NAT 的打洞成功率。Windows 执行方不得无声启用中继。

## 可靠性

UUID 小写标识事件；所有重试使用持久化的同一份密文，否则随机 GCM nonce 会导致服务端 409。小文件 outbox 写入 App Support，源文件先复制进受管目录。UI 只有本地提交后才进入传输队列。

服务端串行提交 index.json，先临时文件后 rename；索引保存全局 seq（即使全部内容过期也不重置）。上传正文读取期间预占配额，提交前再检查；上传中断释放预约，启动清理无索引正文。单实例运行，不能直接横向复制容器。

Mac 约每 2 秒拉取事件，成功接收才推进游标；20 秒检查离线重试。不是 WebSocket，本版本在线同步延迟通常受这一轮询间隔影响；不宣传“零延迟”。接收 envelope 校验密钥、ID、发送者、类型、数量和大小，commit 后持久化 seen 去重。

## 剪贴板

NSPasteboard.changeCount 每 600 ms 检测。默认关闭自动同步，由用户主动开启。优先级：file URL > PNG/TIFF > UTF-8 文本。写入远端内容时同时写 app.ferndrop.remote 标识并记录 changeCount，避免回环。

接收后仅在实时同步开启、事件小于 15 秒、没有未观察到的新复制、没有进行中的小文件发送时自动覆盖。历史补收只写文件与列表。手动点击复制不受年龄限制。图片用 NSImage，普通文件用 NSURL 列表（复制语义，不删除源文件）。文件选择支持多文件；暂不支持复制整个目录、Finder 虚拟文件承诺、富文本格式互转。

当前同一时刻双端复制的处理以避免覆盖未观察到的本地复制为主；尚未实现分布式全序冲突选择器，双端同时复制需要联调后完善。

## 生命周期与资源

普通本地目录 yyyy-MM-dd；大文件独立目录。见 STORAGE.md。云端保留 72 小时、总容量 200,000,000 字节（按密文、含 base64 包装的实际占用计费/计量）。元数据、容器日志、应用索引不包含在此正文配额中，服务器总磁盘仍应留余量。

Mac 窗口关闭隐藏，菜单栏持续运行；退出终止 sendme provider。网络不可达保留本地队列。不默认开机启动、不阻止整机休眠。

## 配对与当前安全范围

AES-256-GCM 的空间密钥与服务端 Bearer token 分开。密钥和令牌存在 Mac Keychain，不在 settings.json。服务器仅拿到密文、设备 UUID、大小与时间；不拿到内容解密密钥。连接公网必须 HTTPS，本机调试允许 loopback HTTP。

v0.1 使用手动受信配对配置，尚未实现新设备审批和独立设备撤销。全体设备共享空间密钥及一个服务器令牌。不能声称已经支持逐设备撤权；要更换空间需处理完待发任务。原生 WebView 仅加载本地界面，CSP 禁止网络脚本/连接，输出文本使用 HTML escape。

## 发布限制

本次交付含 Mac Apple Silicon 本机构建，ad-hoc 签名，无 Apple Developer ID 公证。Intel 需在 Intel Mac 执行 build-mac.sh 和对应 sendme 下载。服务端提供源码与部署文件，尚未部署到用户公网服务器；域名/HTTPS 尚待配置。Windows 外壳属于下一执行阶段，本次不伪造 Windows 编译和跨系统实测结果。
