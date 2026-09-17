# FernDrop

个人 Mac / Windows 剪贴板与文件传输工具。当前仓库提供 Mac 原生应用、共享 HTML/CSS/JS 界面、Node.js 暂存服务及 Windows 实施规格。用户的 Windows 版本已参与局域网联调，但其原生外壳源码尚未合入当前主分支。公网 HTTPS 暂存服务已部署，Mac 已配置连接。

## Mac 本地运行

本次安装位置：`/Applications/FernDrop.app`。在访达“应用程序”中打开 FernDrop。当前交付为 Apple Silicon 本机构建、ad-hoc 签名，未做 Developer ID 公证；未验证旧版 macOS 兼容性。

开发构建需要 Apple Command Line Tools：

```sh
bash scripts/build-mac.sh
open build/FernDrop.app
```

网页预览仅用于界面验证：`npm run preview`，打开 http://127.0.0.1:4173/。实际系统剪贴板和文件操作请在 Mac 应用中使用。

## 使用

接收页可添加文件、粘贴发送和输入文字；启用“同步剪贴板”后监听文本、图片及文件列表。发送页包含大文件直传入口。设置页配置 HTTPS 服务地址、令牌及接收目录；发送页的配对区域可导出凭据交给自己的另一台设备。不要公开配对内容。

传输历史仅保留最近 10 条，更早的历史和待发缓存自动删除；已保存文件沿用下述保留规则。每条标题最多 160 字符且自动省略，复制保留完整内容。普通内容优先尝试局域网直传，失败回退云端；20MB以上走 sendme。云端暂存72小时、总额200MB。普通本地副本按日期归档，自动清理30天前受管目录；大文件不自动清理。详细边界见下列文档。

## 文档

- [架构与功能边界](docs/ARCHITECTURE.md)
- [跨端协议](docs/PROTOCOL.md)
- [存储及清理](docs/STORAGE.md)
- [界面与像素动画规范](docs/DESIGN-SYSTEM.md)
- [Windows 执行单](docs/WINDOWS-HANDOFF.md)
- [验证记录与待完成项](docs/VALIDATION.md)
- [公网部署与续期维护](docs/DEPLOYMENT.md)

## 测试

```sh
npm test
build/FernDrop.app/Contents/MacOS/FernDrop --self-test
node tests/native-integration.mjs
node tests/sendme-integration.mjs
```

最后一项在当前环境曾连接超时，不能视为已通过。局域网已观察到双向接收；Windows 公网与大文件跨网络验收仍待完成，详见验证记录。

Git 仅包含源码、素材、平台参考实现及文档，构建产物忽略。vendor/bin/sendme 是官方 macOS 工具，许可在 vendor/。运行配置、密钥和传输内容不得提交。
