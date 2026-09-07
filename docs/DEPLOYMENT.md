# 当前公网部署

2026-09-07 验证：服务地址 `https://47.108.74.84`，Ubuntu 上由 Nginx 终止可信 TLS，转发至回环地址 `127.0.0.1:8787`。Node 22.23.2 执行 `/opt/ferndrop/server.mjs`，systemd 服务名 `ferndrop`，以独立系统用户运行。密文目录 `/var/lib/ferndrop`，访问令牌仅在受限的 `/etc/ferndrop.env`。空间密钥只在客户端，未放到服务器。

云端总容量 200 MB、保留 72 小时。已测试认证请求和真实密文上传/下载；Windows 仍需导入配对配置并完成异地联调。不要将配对文件、实际令牌或密钥写入本仓库。

## 证书续期

使用 Let's Encrypt 的短期 IP 证书，无需域名；证书有效期约 6 天，因此自动续期是运行要求。证书目录 `/etc/letsencrypt/live/ferndrop-ip/`，Certbot 位于 `/opt/ferndrop-certbot/bin/certbot`。

服务器 `ferndrop-cert-renew.timer` 每日四次尝试续期，成功后部署钩子检查并重载 Nginx。当前服务器直接连接 ACME 存在超时，另有 Mac 辅助路径：

- LaunchAgent：`~/Library/LaunchAgents/app.ferndrop.cert-renew.plist`，登录后启动并每 6 小时执行。
- 维护目录：`~/Library/Application Support/FernDrop/maintenance/`；`renew.sh` 建立仅用于续期的 SSH 反向 SOCKS 通道。
- 专用 SSH 密钥受服务器强制命令和转发限制，不能执行任意远程 shell。服务器入口 `/usr/local/sbin/ferndrop-cert-renew-via-mac`。
- 日志为维护目录的 `renew.log` / `renew-error.log`。2026-09-07 手动调用同一凭据的模拟续期成功。

在服务器出口问题解除前，Mac 需要定期登录并联网，不能连续离线跨过证书有效期。更换 Mac 或移除该 LaunchAgent 前，先恢复服务器独立续期或迁移辅助通道。检查证书应使用正常 TLS 校验，禁止通过关闭证书验证绕过到期问题。

服务器维护命令：

```sh
systemctl status ferndrop nginx ferndrop-cert-renew.timer
journalctl -u ferndrop --since today
openssl x509 -in /etc/letsencrypt/live/ferndrop-ip/fullchain.pem -noout -dates
```
