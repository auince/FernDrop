import AppKit
import WebKit
import CryptoKit

final class App: NSObject,NSApplicationDelegate,WKScriptMessageHandler,WKNavigationDelegate,NSWindowDelegate {
 var window:NSWindow!;var web:WKWebView!;var statusItem:NSStatusItem!;var store:FileStore!;var lan=LAN()
 var key=Data();var token="";var clipboardCount=0;var timer:Timer?;var polling=false;var connected=false;var used=0
 var busy=Set<String>();var processes:[String:Process]=[:];var lastCleanup=Date.distantPast;var seen=Set<String>()
 let pasteboard=NSPasteboard.general;let remoteType=NSPasteboard.PasteboardType("app.ferndrop.remote")
 func applicationDidFinishLaunching(_ notification:Notification){
  do {
   let support=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!.appendingPathComponent("FernDrop")
   store=try FileStore(support:support);seen=Set(store.settings.seen)
   if let saved=Vault.get("spaceKey"),saved.count==32 {key=saved}else{key=SymmetricKey(size:.bits256).withUnsafeBytes{Data($0)};try Vault.set("spaceKey",key)}
   token=Vault.get("relayToken").flatMap{String(data:$0,encoding:.utf8)} ?? ""
   setupWindow();clipboardCount=pasteboard.changeCount
   lan.onPeers={[weak self] _ in self?.push()};lan.onReceive={[weak self] data in
    guard let self else{return nil};do{let e=try unseal(data,key:self.key);guard e.senderID != self.store.settings.deviceID else{return nil};try self.accept(e,route:"局域网直传");let ack=Envelope(id:e.id,senderID:self.store.settings.deviceID,senderName:self.store.settings.deviceName,createdAt:Date().timeIntervalSince1970,kind:"ack",text:"",files:[]);return try seal(ack,key:self.key)}catch{return nil}
   }
   try lan.start(name:store.settings.deviceID)
   timer=Timer.scheduledTimer(withTimeInterval:0.6,repeats:true){[weak self] _ in self?.tick()}
  }catch{let alert=NSAlert();alert.messageText="FernDrop 无法启动";alert.informativeText=error.localizedDescription;alert.runModal();NSApp.terminate(nil)}
 }
 func setupWindow(){
  let config=WKWebViewConfiguration();config.userContentController.add(self,name:"ferndrop")
  web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=self;web.setValue(false,forKey:"drawsBackground")
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:1130,height:850),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
  window.title="FernDrop · 轻轻一传";window.minSize=NSSize(width:880,height:720);window.backgroundColor=NSColor(calibratedRed:0.98,green:0.985,blue:0.97,alpha:1);window.contentView=web;window.delegate=self;window.center();window.makeKeyAndOrderFront(nil)
  let resources=Bundle.main.resourceURL!.appendingPathComponent("ui");web.loadFileURL(resources.appendingPathComponent("index.html"),allowingReadAccessTo:resources)
  let menu=NSMenu(),appMenu=NSMenu();let appItem=NSMenuItem();appItem.submenu=appMenu;menu.addItem(appItem);appMenu.addItem(withTitle:"显示 FernDrop",action:#selector(showWindow),keyEquivalent:"0").target=self;appMenu.addItem(.separator());appMenu.addItem(withTitle:"退出 FernDrop",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
  let edit=NSMenu(title:"编辑"),editItem=NSMenuItem(title:"编辑",action:nil,keyEquivalent:"");editItem.submenu=edit;menu.addItem(editItem)
  for(title,sel,k) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")]{edit.addItem(withTitle:title,action:Selector(sel),keyEquivalent:k)};NSApp.mainMenu=menu
  statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength);statusItem.button?.image=NSImage(systemSymbolName:"leaf",accessibilityDescription:"FernDrop");let sm=NSMenu();sm.addItem(withTitle:"打开 FernDrop",action:#selector(showWindow),keyEquivalent:"").target=self;sm.addItem(withTitle:"粘贴并发送",action:#selector(menuCapture),keyEquivalent:"").target=self;sm.addItem(withTitle:"暂停 / 开启同步",action:#selector(menuToggle),keyEquivalent:"").target=self;sm.addItem(.separator());sm.addItem(withTitle:"退出",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"");statusItem.menu=sm
  NSApp.activate(ignoringOtherApps:true)
 }
 @objc func showWindow(){window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
 @objc func menuCapture(){do{try capture()}catch{event("offline",error.localizedDescription)}}
 @objc func menuToggle(){store.settings.enabled.toggle();clipboardCount=pasteboard.changeCount;try? store.save();push()}
 func windowShouldClose(_ sender:NSWindow)->Bool {sender.orderOut(nil);return false}
 func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {for p in processes.values where p.isRunning{p.terminate()};try? store.save();return .terminateNow}
 func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){decisionHandler(navigationAction.request.url?.isFileURL==true ? .allow:.cancel)}
 func js(_ method:String,_ args:[Any]){guard JSONSerialization.isValidJSONObject(args),let data=try? JSONSerialization.data(withJSONObject:args),let string=String(data:data,encoding:.utf8) else{return};web?.evaluateJavaScript("window.FernDrop && window.FernDrop.\(method)(...\(string))",completionHandler:nil)}
 func event(_ pose:String,_ text:String){js("event",[pose,text])}
 func snapshot()->[String:Any]{["items":object(store.items),"enabled":store.settings.enabled,"deviceName":store.settings.deviceName,"root":store.settings.root,"serverURL":store.settings.serverURL,"platform":"macOS","configured": !store.settings.serverURL.isEmpty && !token.isEmpty,"connected":connected,"used":used,"quota":200_000_000,"peers":lan.candidates.map{_ in "已发现的局域网设备"}]}
 func push(){js("update",[snapshot()])}
 func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){
  guard message.frameInfo.isMainFrame,message.frameInfo.request.url?.isFileURL==true,let b=message.body as? [String:Any],let id=b["id"] as? String,let method=b["method"] as? String else{return}
  let args=b["args"] as? [String:Any] ?? [:]
  Task{@MainActor in do{let result=try await handle(method,args);js("reply",[id,result,NSNull()])}catch{js("reply",[id,NSNull(),error.localizedDescription])}}
 }
 func handle(_ method:String,_ a:[String:Any])async throws->Any {
  switch method {
  case "bootstrap":return snapshot()
  case "toggleSync":menuToggle()
  case "sendText":let text=a["text"] as? String ?? "";guard !text.isEmpty,text.utf8.count<=1_000_000 else{throw failure("文本为空或超过 1 MB")};var item=Transfer(kind:"text",name:String(text.prefix(80)),sender:store.settings.deviceName);item.text=text;item.size=text.utf8.count;enqueue(item)
  case "capture":try capture()
  case "chooseFiles":let panel=NSOpenPanel();panel.allowsMultipleSelection=true;panel.canChooseDirectories=false;if panel.runModal() == .OK{try importURLs(panel.urls,forceLarge:a["forceLarge"] as? Bool ?? false,allowRelay:a["allowRelay"] as? Bool ?? false)}
  case "importFiles":guard let files=a["files"] as? [[String:String]],files.count<=256 else{throw failure("无效文件列表")};var item=Transfer(kind:"file",name:"",sender:store.settings.deviceName);for f in files{guard let d=Data(base64Encoded:f["data"] ?? ""),item.size+d.count<=smallLimit else{throw failure("拖入的文件超过 20 MB，请使用添加文件")};let saved=try store.put(d,name:f["name"] ?? "未命名");item.files.append(saved);item.size+=d.count};guard !item.files.isEmpty else{return false};item.name=item.files.count==1 ? item.files[0].name:"\(item.files.count) 个文件";enqueue(item)
  case "copyItem":guard let item=find(a) else{throw failure("记录不存在")};try copy(item);event("copy","已复制到系统剪贴板")
  case "copyTicket":guard let ticket=find(a)?.ticket else{throw failure("票据尚未生成")};writeText(ticket);event("copy","直传票据已复制")
  case "reveal":guard let path=find(a)?.files.first?.path,FileManager.default.fileExists(atPath:path) else{throw failure("本地文件已清理或移动")};NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:path)])
  case "openRoot":NSWorkspace.shared.open(store.root)
  case "chooseRoot":let p=NSOpenPanel();p.canChooseDirectories=true;p.canChooseFiles=false;p.canCreateDirectories=true;if p.runModal() == .OK,let url=p.url {store.settings.root=url.path;try store.ensureRoot();try store.save();push()}
  case "cleanup":let result=try store.cleanup(protected:protectedPaths());try store.cleanupTemporary(active:busy.union(processes.keys));lastCleanup=Date();event("clean",result);return result
  case "saveSettings":let server=(a["serverURL"] as? String ?? "").trimmingCharacters(in:CharacterSet(charactersIn:"/"));try validateServer(server);let t=a["serverToken"] as? String ?? "";if !t.isEmpty{guard t.count>=24 else{throw failure("访问令牌至少 24 个字符")};try Vault.set("relayToken",Data(t.utf8));token=t};if store.settings.serverURL != server{store.settings.cursor=0};store.settings.serverURL=server;let name=a["deviceName"] as? String ?? "";if !name.isEmpty{store.settings.deviceName=String(name.prefix(60))};try store.save();connected=false;push();Task{await poll()}
  case "exportPairing":guard !token.isEmpty else{throw failure("请先填写同步服务的访问令牌")};let data=try JSONSerialization.data(withJSONObject:["version":1,"serverURL":store.settings.serverURL,"token":token,"spaceKey":key.base64EncodedString()],options:.prettyPrinted);writeText(String(data:data,encoding:.utf8)!)
  case "importPairing":guard let str=a["json"] as? String,let d=str.data(using:.utf8),let v=try JSONSerialization.jsonObject(with:d) as? [String:Any],v["version"] as? Int==1,let k=v["spaceKey"] as? String,let data=Data(base64Encoded:k),data.count==32,let t=v["token"] as? String,t.count>=24,let server=v["serverURL"] as? String else{throw failure("配对信息不完整")};guard busy.isEmpty && processes.isEmpty && !store.items.contains(where:{$0.direction=="out" && ["等待发送","等待重试"].contains($0.status)}) else{throw failure("请先完成待发送任务，再切换空间")};try validateServer(server);try Vault.set("spaceKey",data);try Vault.set("relayToken",Data(t.utf8));key=data;token=t;store.settings.serverURL=server;store.settings.cursor=0;seen=[];store.settings.seen=[];try store.save();push()
  case "retry":if let item=find(a){Task{await transmit(item.id)}}
  case "receiveTicket":let ticket=a["ticket"] as? String ?? "";try receiveSendme(ticket,allowRelay:a["allowRelay"] as? Bool ?? false)
  case "cancelSendme":if let id=a["id"] as? String{processes[id]?.terminate();processes.removeValue(forKey:id);update(id,status:"已停止",detail:"本地文件保留，可重新创建任务")}
  default:throw failure("不支持的操作：\(method)")
  };return true
 }
 func validateServer(_ str:String)throws {if str.isEmpty{return};guard let u=URL(string:str),let host=u.host,u.user==nil,u.password==nil,u.query==nil,u.fragment==nil,u.path.isEmpty||u.path=="/" else{throw failure("请输入服务根地址")};guard u.scheme=="https" || (u.scheme=="http" && ["localhost","127.0.0.1","[::1]","::1"].contains(host)) else{throw failure("公网服务器必须使用 HTTPS")}}
 func find(_ a:[String:Any])->Transfer?{store.items.first{$0.id==a["id"] as? String}}
 func update(_ id:String,status:String,route:String?=nil,detail:String?=nil,ticket:String?=nil){if let i=store.items.firstIndex(where:{$0.id==id}){store.items[i].status=status;if let route{store.items[i].route=route};if let detail{store.items[i].detail=detail};if let ticket{store.items[i].ticket=ticket};try? store.save();push()}}
 func enqueue(_ item:Transfer){store.items.insert(item,at:0);do{try store.save();push();event("send","已保存到本地发送队列");Task{await transmit(item.id)}}catch{event("offline","无法保存队列："+error.localizedDescription)}}
 func writeText(_ text:String){pasteboard.clearContents();pasteboard.setString(text,forType:.string);pasteboard.setString("1",forType:remoteType);clipboardCount=pasteboard.changeCount}
 func copy(_ item:Transfer)throws {
  if item.kind=="text"{writeText(item.text);return}
  guard !item.files.isEmpty,item.files.allSatisfy({FileManager.default.fileExists(atPath:$0.path)}) else{throw failure("文件尚未接收完成或已被清理")}
  if item.kind=="image",let d=try? Data(contentsOf:URL(fileURLWithPath:item.files[0].path)),let image=NSImage(data:d){pasteboard.clearContents();pasteboard.writeObjects([image]);pasteboard.setString(item.id,forType:remoteType)}else{pasteboard.clearContents();pasteboard.writeObjects(item.files.map{NSURL(fileURLWithPath:$0.path)});pasteboard.setString(item.id,forType:remoteType)};clipboardCount=pasteboard.changeCount
 }
 func capture()throws {
  if let urls=pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty {try importURLs(urls);return}
  if let d=pasteboard.data(forType:.png) ?? pasteboard.data(forType:.tiff),let rep=NSBitmapImageRep(data:d),let png=rep.representation(using:.png,properties:[:]){
   var item=Transfer(kind:"image",name:"截图.png",sender:store.settings.deviceName);item.size=png.count;item.large=png.count>smallLimit;item.files=[try store.put(png,name:"截图.png",large:item.large)];item.name=item.files[0].name;item.preview=thumbnail(png)
   if item.large{store.items.insert(item,at:0);try store.save();try startSendme(item,allowRelay:false)}else{enqueue(item)};return
  }
  if let text=pasteboard.string(forType:.string),!text.isEmpty{guard text.utf8.count<=1_000_000 else{throw failure("文本超过 1 MB")};var item=Transfer(kind:"text",name:String(text.prefix(80)),sender:store.settings.deviceName);item.text=text;item.size=text.utf8.count;enqueue(item);return};throw failure("剪贴板没有可发送的文本、图片或普通文件")
 }
 func thumbnail(_ data:Data)->String? {guard let source=NSImage(data:data) else{return nil};let image=NSImage(size:NSSize(width:80,height:80));image.lockFocus();source.draw(in:NSRect(x:0,y:0,width:80,height:80));image.unlockFocus();return image.tiffRepresentation.flatMap{NSBitmapImageRep(data:$0)?.representation(using:.png,properties:[:])}?.base64EncodedString()}
 func importURLs(_ urls:[URL],forceLarge:Bool=false,allowRelay:Bool=false)throws {
  guard urls.count<=256 else{throw failure("每批最多 256 个文件")};let total=try urls.reduce(0){try $0+($1.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)};let large=forceLarge||total>smallLimit
  var item=Transfer(kind:"file",name:"",sender:store.settings.deviceName);item.large=large;item.size=total
  for u in urls{item.files.append(try store.importFile(u,large:large))};item.name=item.files.count==1 ? item.files[0].name:"\(item.files.count) 个文件"
  if large{store.items.insert(item,at:0);try store.save();push();try startSendme(item,allowRelay:allowRelay)}else{enqueue(item)}
 }
 func wire(_ item:Transfer)throws->Envelope {
  let files=try item.files.map{WireFile(name:$0.name,data:try Data(contentsOf:URL(fileURLWithPath:$0.path)).base64EncodedString())}
  return Envelope(id:item.id,senderID:store.settings.deviceID,senderName:item.sender,createdAt:item.createdAt,kind:item.kind,text:item.text,files:files)
 }
 func transmit(_ id:String)async {
  guard !busy.contains(id),let item=store.items.first(where:{$0.id==id}),!item.large else{return};busy.insert(id);defer{busy.remove(id)}
  do {let outbox=store.support.appendingPathComponent("outbox");try FileManager.default.createDirectory(at:outbox,withIntermediateDirectories:true);let path=outbox.appendingPathComponent(id);let payload:Data
   if FileManager.default.fileExists(atPath:path.path){payload=try Data(contentsOf:path)}else{payload=try seal(wire(item),key:key);try payload.write(to:path,options:.atomic)}
   try await deliver(payload,id:id);event("success","内容已送达传输通道")}catch{update(id,status:"等待重试",detail:error.localizedDescription);event("offline",error.localizedDescription)}
 }
 func deliver(_ payload:Data,id:String)async throws {
  update(id,status:"探测局域网",detail:"")
  let currentKey=key
  let direct=await lan.send(payload){data in guard let ack=try? unseal(data,key:currentKey) else{return false};return ack.kind=="ack" && ack.id==id}
  if direct{update(id,status:"对端已接收",route:"局域网直传",detail:"");return}
  guard !store.settings.serverURL.isEmpty,!token.isEmpty else{throw failure("尚未配置云端，内容已保留在本地")}
  update(id,status:"上传中",route:"云端暂存")
  _=try await request("PUT",path:"/v1/items/"+id,data:payload);update(id,status:"已暂存 · 3 天",route:"云端暂存",detail:"")
 }
 func request(_ method:String,path:String,data:Data?=nil)async throws->Data {
  guard let url=URL(string:store.settings.serverURL+path) else{throw failure("无效服务器地址")};var r=URLRequest(url:url);r.httpMethod=method;r.timeoutInterval=45;r.setValue("Bearer "+token,forHTTPHeaderField:"Authorization");r.setValue(store.settings.deviceID,forHTTPHeaderField:"X-Device-ID");r.httpBody=data;if let data{r.setValue(String(data.count),forHTTPHeaderField:"Content-Length");r.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")}
  let (bytes,response)=try await URLSession.shared.data(for:r);guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else{let code=(response as? HTTPURLResponse)?.statusCode ?? 0;throw failure(code==507 ? "云端 200 MB 空间已满，本地文件保留":code==401 ? "服务器访问令牌不正确":"服务器请求失败（\(code)）")};return bytes
 }
 func accept(_ e:Envelope,route:String)throws {
  guard !seen.contains(e.id),e.senderID != store.settings.deviceID else{return}
  if e.kind=="ticket" {guard let ticket=e.ticket else{throw failure("缺少直传票据")};try receiveSendme(ticket,allowRelay:e.allowRelay ?? false,id:e.id,sender:e.senderName);seen.insert(e.id);store.settings.seen=Array(seen);try store.save();return}
  var item=Transfer(kind:e.kind,name:"",sender:e.senderName);item.id=e.id;item.createdAt=e.createdAt;item.text=e.text;item.direction="in";item.route=route;item.status="已接收"
  var decoded:[(String,Data)]=[];var total=e.text.utf8.count
  for f in e.files{guard let d=Data(base64Encoded:f.data) else{throw failure("文件数据损坏")};total+=d.count;guard total<=smallLimit else{throw failure("接收内容超过小文件限制")};decoded.append((f.name,d))}
  for(name,data)in decoded{item.files.append(try store.put(data,name:name));if e.kind=="image"{item.preview=thumbnail(data)}}
  item.size=total;item.name=e.kind=="text" ? String(e.text.prefix(80)):item.files.count==1 ? item.files[0].name:"\(item.files.count) 个文件"
  store.items.insert(item,at:0);seen.insert(e.id);store.settings.seen=Array(seen);try store.save()
  let age=Date().timeIntervalSince1970-e.createdAt
  // Do not overwrite an unobserved local copy, stale backfill, or pending outgoing intent.
  if store.settings.enabled && age>=0 && age<15 && pasteboard.changeCount==clipboardCount && busy.isEmpty {try copy(item)}
  push();event("receive","收到来自 \(e.senderName) 的内容")
 }
 func protectedPaths()->Set<String>{var paths=Set((pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []).map(\.path));for item in store.items where busy.contains(item.id)||processes[item.id] != nil || (item.direction=="out" && ["等待发送","等待重试","上传中"].contains(item.status)){for file in item.files{paths.insert(file.path)}};return paths}
 func tick(){
  if store.settings.enabled && pasteboard.changeCount != clipboardCount {clipboardCount=pasteboard.changeCount;if pasteboard.string(forType:remoteType)==nil{do{try capture()}catch{event("offline",error.localizedDescription)}}}
  if !polling{Task{await poll()}}
  if Date().timeIntervalSince(lastCleanup)>86400 {lastCleanup=Date();do{_=try store.cleanup(protected:protectedPaths());try store.cleanupTemporary(active:busy.union(processes.keys))}catch{event("offline","清理暂缓："+error.localizedDescription)}}
 }
 var lastPoll=Date.distantPast;var lastRetry=Date.distantPast
 func poll()async {
  guard !polling,!store.settings.serverURL.isEmpty,!token.isEmpty,Date().timeIntervalSince(lastPoll)>2 else{return};polling=true;lastPoll=Date();defer{polling=false}
  do {
   let data=try await request("GET",path:"/v1/events?after=\(store.settings.cursor)")
   guard let result=try JSONSerialization.jsonObject(with:data) as? [String:Any],let events=result["events"] as? [[String:Any]],let cursor=result["cursor"] as? Int else{throw failure("服务器协议不匹配")}
   for entry in events {guard let id=entry["id"] as? String,let sender=entry["sender"] as? String else{continue};if sender==store.settings.deviceID || seen.contains(id){continue};let bytes=try await request("GET",path:"/v1/items/"+id);let e=try unseal(bytes,key:key);guard e.id==id,e.senderID==sender else{throw failure("传输身份不匹配")};try accept(e,route:"云端暂存")}
   store.settings.cursor=cursor;try store.save();connected=true
   if let s=try? await request("GET",path:"/v1/status"),let v=try? JSONSerialization.jsonObject(with:s) as? [String:Any]{used=v["used"] as? Int ?? 0}
   if Date().timeIntervalSince(lastRetry)>20 {lastRetry=Date();for item in store.items.filter({$0.direction=="out" && !$0.large && ["等待发送","等待重试"].contains($0.status)}).prefix(3){await transmit(item.id)}}
  }catch{connected=false};push()
 }
 func sendmePath()throws->URL{let p=Bundle.main.resourceURL!.appendingPathComponent("bin/sendme");guard FileManager.default.isExecutableFile(atPath:p.path) else{throw failure("未找到 sendme，请运行 scripts/install-sendme.sh 后重新打包")};return p}
 func startSendme(_ item:Transfer,allowRelay:Bool)throws {
  let base=store.support.appendingPathComponent("sendme/"+item.id);try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
  var target=URL(fileURLWithPath:item.files[0].path)
  if item.files.count>1{target=base.appendingPathComponent("文件合集");try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true);for f in item.files{try FileManager.default.linkItem(at:URL(fileURLWithPath:f.path),to:store.unique(f.name,in:target))}}
  try launchSendme(id:item.id,args:["send",target.path,"--relay",allowRelay ? "default":"disabled","--no-progress"],cwd:base,receive:false,allowRelay:allowRelay)
 }
 func receiveSendme(_ ticket:String,allowRelay:Bool,id:String=UUID().uuidString.lowercased(),sender:String="直传设备")throws {
  guard ticket.hasPrefix("blob"),ticket.count<10000,ticket.range(of:"^[A-Za-z0-9]+$",options:.regularExpression) != nil else{throw failure("请输入完整 blob 票据")}
  if store.items.contains(where:{$0.id==id}){return}
  var item=Transfer(kind:"transfer",name:"正在接收大文件",sender:sender);item.id=id;item.large=true;item.direction="in";item.route=allowRelay ? "sendme · 允许中继":"sendme · 仅直连";item.status="连接中";store.items.insert(item,at:0);try store.save();push()
  let cwd=store.support.appendingPathComponent("sendme/"+id);try FileManager.default.createDirectory(at:cwd,withIntermediateDirectories:true)
  try launchSendme(id:id,args:["receive",ticket,"--relay",allowRelay ? "default":"disabled","--no-progress"],cwd:cwd,receive:true,allowRelay:allowRelay)
 }
 func launchSendme(id:String,args:[String],cwd:URL,receive:Bool,allowRelay:Bool)throws {
  let p=Process(),pipe=Pipe();p.executableURL=try sendmePath();p.arguments=args;p.currentDirectoryURL=cwd;p.standardOutput=pipe;p.standardError=pipe;var output="";var published=false
  pipe.fileHandleForReading.readabilityHandler={[weak self] h in let data=h.availableData;guard !data.isEmpty else{return};let chunk=String(decoding:data,as:UTF8.self);DispatchQueue.main.async{guard let self else{return};output=String((output+chunk).suffix(16000));try? Data(output.utf8).write(to:cwd.appendingPathComponent(".ferndrop-transfer.log"),options:.atomic);self.update(id,status:receive ? "接收中":"等待对端",route:allowRelay ? "sendme · 允许中继":"sendme · 仅直连",detail:receive ? "正在连接或接收，完成后自动保存到大文件目录":"发送端保持运行，另一台设备可通过票据接收")
   if !receive && !published,let range=output.range(of:"blob[a-zA-Z0-9]{40,}",options:.regularExpression){published=true;let ticket=String(output[range]);self.update(id,status:"等待对端",detail:"票据已生成，发送端需保持在线",ticket:ticket)
    let e=Envelope(id:id,senderID:self.store.settings.deviceID,senderName:self.store.settings.deviceName,createdAt:Date().timeIntervalSince1970,kind:"ticket",text:"",files:[],ticket:ticket,allowRelay:allowRelay)
    Task{@MainActor in do{let data=try seal(e,key:self.key);try await self.deliver(data,id:id);self.update(id,status:"等待对端",route:allowRelay ? "sendme · 允许中继":"sendme · 仅直连")}catch{self.update(id,status:"票据就绪",detail:"可手动复制票据；"+error.localizedDescription)}}
   }
  }}
  p.terminationHandler={[weak self] process in pipe.fileHandleForReading.readabilityHandler=nil;DispatchQueue.main.async{guard let self else{return};self.processes.removeValue(forKey:id)
   if receive && process.terminationStatus==0 {do{let files=try FileManager.default.contentsOfDirectory(at:cwd,includingPropertiesForKeys:nil).filter{!$0.lastPathComponent.hasPrefix(".")};guard !files.isEmpty else{throw failure("sendme 未产生接收文件")};let dest=try self.store.directory(large:true);var refs:[TransferFile]=[];for f in files{let target=self.store.unique(f.lastPathComponent,in:dest);try FileManager.default.moveItem(at:f,to:target);let size=(try? target.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0;refs.append(TransferFile(name:target.lastPathComponent,path:target.path,size:size))};if let idx=self.store.items.firstIndex(where:{$0.id==id}){self.store.items[idx].files=refs;self.store.items[idx].kind="file";self.store.items[idx].name=refs.count==1 ? refs[0].name:"\(refs.count) 个文件";self.store.items[idx].size=refs.reduce(0){$0+$1.size}};self.update(id,status:"已接收",detail:"");self.event("success","大文件已保存到本地")}catch{self.update(id,status:"保存失败",detail:error.localizedDescription)}}
   else{self.update(id,status:process.terminationStatus==0 ? "已结束":"已停止或连接失败",detail:process.terminationStatus==0 ? "任务已结束":"未完成传输。请确认对端在线，或尝试允许加密中继。")}
  }}
  processes[id]=p;do{try p.run();update(id,status:"连接中",route:allowRelay ? "sendme · 允许中继":"sendme · 仅直连")}catch{processes.removeValue(forKey:id);update(id,status:"启动失败",detail:error.localizedDescription);throw error}
 }
}

extension App {
 func integrationTest(server:String,temp:URL)async throws {
  store=try FileStore(support:temp.appendingPathComponent("support"),initialRoot:temp.appendingPathComponent("received"));store.settings.root=temp.appendingPathComponent("received").path;try store.ensureRoot()
  key=Data(repeating:42,count:32);token="ferndrop-integration-token-000001";store.settings.serverURL=server
  let source=temp.appendingPathComponent("test.txt");try Data("文件内容 🌿".utf8).write(to:source)
  var outgoing=Transfer(kind:"file",name:"test.txt",sender:"测试 Mac");outgoing.files=[try store.importFile(source,large:false)];outgoing.size=outgoing.files[0].size;store.items=[outgoing]
  await transmit(outgoing.id);guard store.items[0].status=="已暂存 · 3 天" else{throw failure("上传失败："+(store.items[0].detail ?? ""))}
  await transmit(outgoing.id);guard store.items[0].status=="已暂存 · 3 天" else{throw failure("幂等重试失败")};let payload=try await request("GET",path:"/v1/items/"+outgoing.id),decoded=try unseal(payload,key:key)
  guard decoded.files.count==1,Data(base64Encoded:decoded.files[0].data)==Data("文件内容 🌿".utf8) else{throw failure("上传内容不一致")}
  let incoming=Envelope(id:UUID().uuidString.lowercased(),senderID:UUID().uuidString.lowercased(),senderName:"Windows fixture",createdAt:Date().timeIntervalSince1970,kind:"file",text:"",files:decoded.files)
  try accept(incoming,route:"测试");try accept(incoming,route:"重复测试")
  guard store.items.count==2,store.items[0].files[0].name=="test (1).txt" else{throw failure("入站去重或重命名失败")}
  let pb=NSPasteboard.general;let previous=(pb.pasteboardItems ?? []).map{item -> NSPasteboardItem in let copy=NSPasteboardItem();for t in item.types{if let d=item.data(forType:t){copy.setData(d,forType:t)}};return copy}
  defer{pb.clearContents();pb.writeObjects(previous)}
  try copy(store.items[0]);let urls=pb.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]
  guard urls?.first?.lastPathComponent=="test (1).txt" else{throw failure("文件剪贴板写入失败")}
  let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:4,pixelsHigh:4,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:16,bitsPerPixel:32)!
  memset(bitmap.bitmapData!,180,64);let png=bitmap.representation(using:.png,properties:[:])!
  let im=Envelope(id:UUID().uuidString.lowercased(),senderID:incoming.senderID,senderName:"Windows fixture",createdAt:Date().timeIntervalSince1970,kind:"image",text:"",files:[WireFile(name:"pixel.png",data:png.base64EncodedString())])
  try accept(im,route:"测试");try copy(store.items[0]);guard NSImage(pasteboard:pb) != nil else{throw failure("图片剪贴板写入失败")}
  var txt=Transfer(kind:"text",name:"test",sender:"test");txt.text="跨平台中文 🌿";try copy(txt);guard pb.string(forType:.string)==txt.text else{throw failure("文本剪贴板写入失败")}
  print("PASS: native HTTPS client (loopback HTTP test), encrypted upload/download, incoming file commit, deduplication, collision rename, text/image/file pasteboard writes (previous clipboard restored)")
 }
}
