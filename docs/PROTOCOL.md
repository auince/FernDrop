# FernDrop 协议 v1（Windows 必须精确遵守）

## 原生桥接

前端调用 JSON：`{id: string, method: string, args: object}`。
Mac：`window.webkit.messageHandlers.ferndrop.postMessage(message)`。
Windows：`window.chrome.webview.postMessage(message)`。
Windows 回复：`{type:"reply",id,result,error:null}` 或 `{type:"reply",id,result:null,error:"用户可读错误"}`。
状态推送：`{type:"state",state:Snapshot}`；事件：`{type:"event",event:"receive",message:"已收到文件"}`。
Mac 使用等价 `window.FernDrop.reply/update/event`。响应与请求 id 一一对应，错误路径也必须回复。UI 120 秒超时，但文件传输是后台任务，不能让整个传输生命周期阻塞 RPC。

| method | args | 返回与作用 |
|---|---|---|
| bootstrap | {} | Snapshot，不返回 token/key |
| toggleSync | {} | 切换实时监听，推送状态 |
| sendText | {text} | 本地入队后 true |
| capture | {} | 读取当前系统剪贴板并发送 |
| chooseFiles | {forceLarge?:bool,allowRelay?:bool} | 原生多文件选择与入队 |
| importFiles | {files:[{name,data}]} | 前端拖入，base64，整批 <=20MB |
| copyItem | {id} | 将记录内容写到系统剪贴板 |
| copyTicket | {id} | 复制 sendme 票据，抑制回环 |
| reveal | {id} | 在文件管理器显示对应文件 |
| openRoot | {} | 打开接收根目录 |
| chooseRoot | {} | 原生目录选择并保存 |
| cleanup | {} | 执行受管目录清理，返回描述字符串 |
| saveSettings | {serverURL,serverToken,deviceName} | 空 token 保留原值；修改地址重置游标 |
| exportPairing | {} | 配对配置写剪贴板，不经网页返回密钥 |
| importPairing | {json} | 验证配置，安全保存；有待发任务时拒绝换空间 |
| retry | {id} | 重试同一密文 |
| receiveTicket | {ticket,allowRelay} | 创建 sendme 接收任务 |
| cancelSendme | {id} | 停止任务，保留已接收的最终文件 |

Snapshot：`items:[Transfer], enabled:bool, deviceName:string, platform:string, root:string, serverURL:string, configured:bool, connected:bool, used:int, quota:int, peers:[string]`。

Transfer：`id,kind,name,text,size,route,status,createdAt,sender,direction,files,large,ticket?,detail?,preview?`。
kind 为 text/image/file/transfer；direction out/in；createdAt 是 Unix **秒**（Double）；files 是本地 `{name,path,size}`；preview 是小 PNG 的 base64。服务器时间另用毫秒，切勿混淆。

UI 渲染状态文案，不负责业务分支。v1 为兼容已交付 Mac，状态值使用源码中的中文字符串；后续若迁移为枚举，需要双方同时升级协议。

## 加密内容格式

UTF-8 JSON Envelope：

```json
{
  "version": 1,
  "id": "a1e51651-cad7-4bfd-9686-4b1ec3218546",
  "senderID": "675d2a9a-cef3-4c4c-8f7f-59f386c10332",
  "senderName": "我的 Mac",
  "createdAt": 1788600000.0,
  "kind": "file",
  "text": "",
  "files": [{"name":"example.txt","data":"aGVsbG8="}]
}
```

kind text：text 有值，files=[]。
kind image：files 含一个 PNG。
kind file：files 为多个普通文件，总原始字节 <=20,000,000。
kind ticket：files=[]、ticket 为 sendme 原始 `blob...` 字符串、allowRelay 为布尔。
kind ack：仅 LAN 回执，id 回显源事件 id，senderID 为接收端设备 id。

使用 AES-256-GCM，空间密钥 32 字节，每个新 envelope 随机 nonce 12 字节，tag 16 字节，无附加 AAD。线上二进制布局：`nonce[12] || ciphertext[N] || tag[16]`，对应 CryptoKit `.combined`。文件内容在 JSON 中是标准 base64，整个 JSON 再加密。相同事件重试必须重用原始密文。

## 云端 HTTP

公网 TLS 终止在 Caddy。Header：`Authorization: Bearer <token>`，上传另加 `X-Device-ID: <lowercase UUID>`。

| 方法/路径 | 请求/响应 |
|---|---|
| GET /health | 无鉴权，{ok:true,protocol:1} |
| GET /v1/status | {used,quota,ttlSeconds,items} |
| PUT /v1/items/{id} | application/octet-stream，加密二进制，必须 Content-Length |
| GET /v1/items/{id} | 加密二进制 |
| GET /v1/events?after=N | {cursor,events:[{id,sender,bytes,seq,createdAt,expiresAt}]} |

服务端 createdAt/expiresAt 为 Unix 毫秒。PUT 成功 201；相同 id/相同密文重试 200；同 id/不同内容 409。401 未授权，410 已过期或不存在，413 大小非法，507 总配额不足。PUT 合法正文 29–28,000,000 字节。UUID 不得用作任意相对路径。

游标严格单调递增并持久化，不随过期清理归零。仅在这一批所有待处理入站成功落盘/记录之后推进 cursor。自己的事件跳过；已见事件跳过。文件名和正文在云端不可读。

## LAN

Bonjour DNS-SD 类型 `_ferndrop._tcp`，服务名为 deviceID，端口由系统分配。忽略自己。TCP 数据帧为四字节无符号大端长度 + 加密 envelope，最大帧 28 MB。候选不是可信设备，只有能用空间密钥解密并返回有效加密 ack 才能被视为接收成功。

读帧需累积碎片，不假设一个 TCP read 返回全部内容。总读超时 30 秒；Mac 候选直传尝试约 3 秒后可退云端，重复收件由 id 去重。Windows 实现相同发现服务、TCP framing、ACK，不仅比较 IP 段或公网地址。

当前使用局域网广播发现，未实现云端地址交换；禁止把 VPN 的相同出口误当成同一 LAN。网络候选更新由 NWBrowser 处理。

## 配对

```json
{"version":1,"serverURL":"https://drop.example.com","token":"...","spaceKey":"32-byte-key-in-base64"}
```

这是凭据，不进入仓库、日志、截图或测试报告。设备 id 在各端独立生成，不随配对复制。Windows 使用 DPAPI CurrentUser 或系统凭据存储；服务器令牌与空间密钥分别保存。

`windows/crypto-fixture.json` 仅包含明确的测试密钥，可用于两端协议校验，绝不用于实际配对。
