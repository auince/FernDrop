import Foundation
import CryptoKit
import Security

let smallLimit = 20_000_000
struct TransferFile: Codable { var name: String; var path: String; var size: Int }
struct Transfer: Codable {
 var id = UUID().uuidString.lowercased(); var kind: String; var name: String; var text = ""; var size = 0
 var route = "本地"; var status = "等待发送"; var createdAt = Date().timeIntervalSince1970
 var sender: String; var direction = "out"; var files: [TransferFile] = []; var large = false
 var ticket: String?; var detail: String?; var preview: String?
}
struct WireFile: Codable { var name: String; var data: String }
struct Envelope: Codable {
 var version = 1; var id: String; var senderID: String; var senderName: String; var createdAt: Double
 var kind: String; var text: String; var files: [WireFile]; var ticket: String?; var allowRelay: Bool?
}
struct Settings: Codable {
 var deviceID=UUID().uuidString.lowercased();var deviceName="我的 Mac";var serverURL="";var enabled=false
 var root=FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first!.appendingPathComponent("FernDrop").path
 var cursor=0;var seen:[String]=[]
}
func failure(_ message:String)->NSError { NSError(domain:"FernDrop",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
func object<T: Encodable>(_ value:T)->Any { (try? JSONSerialization.jsonObject(with:JSONEncoder().encode(value))) ?? [:] }
final class Vault {
 static func set(_ key:String,_ value:Data)throws {
  let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.ferndrop.private",kSecAttrAccount as String:key]
  let status=SecItemUpdate(q as CFDictionary,[kSecValueData as String:value] as CFDictionary)
  if status==errSecItemNotFound {var add=q;add[kSecValueData as String]=value;add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;let s=SecItemAdd(add as CFDictionary,nil);if s != errSecSuccess{throw failure("无法保存钥匙串：\(s)")}}
  else if status != errSecSuccess {throw failure("无法更新钥匙串：\(status)")}
 }
 static func get(_ key:String)->Data? {var item:CFTypeRef?;let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.ferndrop.private",kSecAttrAccount as String:key,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne];return SecItemCopyMatching(q as CFDictionary,&item)==errSecSuccess ? item as? Data:nil}
}
final class FileStore {
 let fm=FileManager.default;let support:URL;var settings:Settings;var items:[Transfer]
 init(support:URL,initialRoot:URL?=nil)throws {
  self.support=support;try fm.createDirectory(at:support,withIntermediateDirectories:true)
  let s=support.appendingPathComponent("settings.json"),h=support.appendingPathComponent("history.json")
  settings=fm.fileExists(atPath:s.path) ? try JSONDecoder().decode(Settings.self,from:Data(contentsOf:s)):Settings()
  if !fm.fileExists(atPath:s.path),let initialRoot{settings.root=initialRoot.path}
  items=fm.fileExists(atPath:h.path) ? try JSONDecoder().decode([Transfer].self,from:Data(contentsOf:h)):[]
  try ensureRoot();try save()
 }
 var root:URL {URL(fileURLWithPath:settings.root,isDirectory:true)}
 func ensureRoot()throws {try fm.createDirectory(at:root,withIntermediateDirectories:true);try fm.createDirectory(at:root.appendingPathComponent("大文件"),withIntermediateDirectories:true)}
 func save()throws {try JSONEncoder().encode(settings).write(to:support.appendingPathComponent("settings.json"),options:.atomic);try JSONEncoder().encode(items).write(to:support.appendingPathComponent("history.json"),options:.atomic)}
 func directory(large:Bool,date:Date=Date())throws->URL {
  let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd"
  let dir=root.appendingPathComponent(large ? "大文件":formatter.string(from:date));try fm.createDirectory(at:dir,withIntermediateDirectories:true)
  if !large {let marker=dir.appendingPathComponent(".ferndrop-managed");if !fm.fileExists(atPath:marker.path){try Data("FernDrop directory v1".utf8).write(to:marker,options:.atomic)}}
  return dir
 }
 static func safeName(_ name:String)->String {
  let trimmed=name.replacingOccurrences(of:"\\",with:"_").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:":",with:"_").replacingOccurrences(of:"\0",with:"")
  let clean=String(trimmed.unicodeScalars.filter{!CharacterSet.controlCharacters.contains($0)}).trimmingCharacters(in:.whitespacesAndNewlines)
  return clean.isEmpty || clean=="." || clean==".." || clean.hasPrefix(".ferndrop") ? "未命名文件":String(clean.prefix(180))
 }
 func unique(_ name:String,in directory:URL)->URL {
  let clean=Self.safeName(name),url=URL(fileURLWithPath:clean),ext=url.pathExtension,stem=url.deletingPathExtension().lastPathComponent
  var n=0,path=directory.appendingPathComponent(clean)
  while fm.fileExists(atPath:path.path){n+=1;path=directory.appendingPathComponent(stem+" (\(n))"+(ext.isEmpty ? "":"."+ext))}
  return path
 }
 func put(_ data:Data,name:String,large:Bool=false)throws->TransferFile {
  let dir=try directory(large:large);let target=unique(name,in:dir)
  // All filesystem commits happen on the main actor, and the write is exclusive.
  let staging=dir.appendingPathComponent(".ferndrop-incoming-"+UUID().uuidString);defer{try? fm.removeItem(at:staging)};try data.write(to:staging,options:.atomic);try fm.moveItem(at:staging,to:target);return TransferFile(name:target.lastPathComponent,path:target.path,size:data.count)
 }
 func importFile(_ source:URL,large:Bool)throws->TransferFile {
  let v=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]);guard v.isRegularFile==true,v.isSymbolicLink != true else{throw failure("当前版本请选择普通文件；不接收符号链接或文件夹")}
  let dir=try directory(large:large),target=unique(source.lastPathComponent,in:dir);try fm.copyItem(at:source,to:target)
  return TransferFile(name:target.lastPathComponent,path:target.path,size:v.fileSize ?? 0)
 }
 func cleanupTemporary(active:Set<String>,now:Date=Date())throws {
  let cutoff=now.addingTimeInterval(-30*86400)
  for area in ["outbox","sendme"] {
   let dir=support.appendingPathComponent(area);guard fm.fileExists(atPath:dir.path) else{continue}
   for child in try fm.contentsOfDirectory(at:dir,includingPropertiesForKeys:[.contentModificationDateKey,.isSymbolicLinkKey]) {
    guard UUID(uuidString:child.lastPathComponent) != nil,!active.contains(child.lastPathComponent) else{continue}
    let v=try child.resourceValues(forKeys:[.contentModificationDateKey,.isSymbolicLinkKey]);if v.isSymbolicLink != true,(v.contentModificationDate ?? now)<cutoff{try? fm.removeItem(at:child)}
   }
  }
 }
 func cleanup(protected:Set<String>=[],now:Date=Date())throws->String {
  let cal=Calendar.current,cutoff=cal.date(byAdding:.day,value:-30,to:cal.startOfDay(for:now))!
  let fmt=DateFormatter();fmt.locale=Locale(identifier:"en_US_POSIX");fmt.dateFormat="yyyy-MM-dd";fmt.isLenient=false
  var removed=0,skipped=0
  for dir in try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey]) {
   let n=dir.lastPathComponent;guard n.range(of:"^\\d{4}-\\d{2}-\\d{2}$",options:.regularExpression) != nil,let date=fmt.date(from:n),date<cutoff else{continue}
   let v=try dir.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]);guard v.isDirectory==true,v.isSymbolicLink != true,fm.fileExists(atPath:dir.appendingPathComponent(".ferndrop-managed").path) else{continue}
   let canonical=dir.resolvingSymlinksInPath().path
   if protected.contains(where:{let p=URL(fileURLWithPath:$0).resolvingSymlinksInPath().path;return p==canonical||p.hasPrefix(canonical+"/")}){skipped+=1;continue}
   do {try fm.removeItem(at:dir);removed+=1}catch{skipped+=1}
  }
  return "已清理 \(removed) 个过期目录；暂缓 \(skipped) 个。大文件目录保持不变。"
 }
}
func seal(_ env:Envelope,key:Data)throws->Data {guard key.count==32 else{throw failure("空间密钥必须为 32 字节")};return try AES.GCM.seal(JSONEncoder().encode(env),using:SymmetricKey(data:key)).combined!}
func unseal(_ data:Data,key:Data)throws->Envelope {
 let clear=try AES.GCM.open(AES.GCM.SealedBox(combined:data),using:SymmetricKey(data:key));let e=try JSONDecoder().decode(Envelope.self,from:clear)
 guard e.version==1,UUID(uuidString:e.id) != nil,UUID(uuidString:e.senderID) != nil,["text","image","file","ticket","ack"].contains(e.kind) else{throw failure("无效传输协议")}
 guard e.files.count<=256 else{throw failure("文件数量超出限制")};return e
}
func validatePairingCloud(server:String,token:String)throws {
 if server.isEmpty {
  guard token.isEmpty else{throw failure("配对配置含令牌但缺少服务器地址；仅局域网配对请将两项都留空")}
 } else {
  guard token.count>=24 else{throw failure("云端配对缺少有效访问令牌，令牌至少需要 24 个字符")}
 }
}
struct PairingConfiguration {
 let key:Data,token:String,server:String
 static func parse(_ text:String)throws->PairingConfiguration {
  guard let bytes=text.data(using:.utf8),let object=try? JSONSerialization.jsonObject(with:bytes),let v=object as? [String:Any] else{throw failure("配对 JSON 格式不正确，请复制完整的 {…}，不要包含列表符号或代码围栏")}
  guard v["version"] as? Int==1 else{throw failure("不支持的配对配置版本")}
  guard let raw=v["spaceKey"] as? String,let key=Data(base64Encoded:raw),key.count==32 else{throw failure("空间密钥无效，需要 Base64 编码的 32 字节密钥")}
  guard let rawServer=v["serverURL"] as? String,let rawToken=v["token"] as? String else{throw failure("缺少 serverURL 或 token 字段；仅局域网配对时两者填写空字符串")}
  let server=rawServer.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"/")),token=rawToken.trimmingCharacters(in:.whitespacesAndNewlines)
  try validatePairingCloud(server:server,token:token)
  return PairingConfiguration(key:key,token:token,server:server)
 }
}
func runCoreTests()throws {
 // Synthetic pairing credentials only; never test with a user's exported key.
 let testKey=Data(repeating:42,count:32).base64EncodedString()
 func config(_ server:String,_ token:String)->String {String(data:try! JSONSerialization.data(withJSONObject:["version":1,"serverURL":server,"token":token,"spaceKey":testKey]),encoding:.utf8)!}
 let lan=try PairingConfiguration.parse(config("",""));precondition(lan.server.isEmpty && lan.token.isEmpty && lan.key.count==32)
 let cloud=try PairingConfiguration.parse(config("https://example.com/",String(repeating:"x",count:24)));precondition(cloud.server=="https://example.com")
 for invalid in [config("https://example.com",""),config("",String(repeating:"x",count:24)),String(config("","").dropLast()),"- "+config("","")] {
  var rejected=false;do{_=try PairingConfiguration.parse(invalid)}catch{rejected=true};precondition(rejected)
 }
 print("PASS: LAN-only pairing, cloud pairing, missing cloud credentials and malformed JSON rejection")
 let temp=FileManager.default.temporaryDirectory.appendingPathComponent("ferndrop-test-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:temp)}
 let s=try FileStore(support:temp.appendingPathComponent("support"),initialRoot:temp.appendingPathComponent("received"));s.settings.root=temp.appendingPathComponent("received").path;try s.ensureRoot()
 let a=try s.put(Data("a".utf8),name:"报告.docx"),b=try s.put(Data("b".utf8),name:"报告.docx");precondition(a.path != b.path && b.name=="报告 (1).docx")
 precondition(FileStore.safeName("../../escape").contains("/")==false)
 let old=Calendar.current.date(byAdding:.day,value:-31,to:Date())!;let oldDir=try s.directory(large:false,date:old);let held=oldDir.appendingPathComponent("held.txt");try Data().write(to:held)
 _=try s.cleanup(protected:[held.path]);guard FileManager.default.fileExists(atPath:held.path) else{throw failure("protected file deleted")};_=try s.cleanup();guard !FileManager.default.fileExists(atPath:oldDir.path) else{throw failure("expired directory not deleted") }
 let big=try s.put(Data(),name:"永久.bin",large:true);_=try s.cleanup(now:Date().addingTimeInterval(90*86400));precondition(FileManager.default.fileExists(atPath:big.path))
 let unmanaged=s.root.appendingPathComponent("2000-01-01");try FileManager.default.createDirectory(at:unmanaged,withIntermediateDirectories:true);_=try s.cleanup();precondition(FileManager.default.fileExists(atPath:unmanaged.path))
 let key=Data(repeating:7,count:32),e=Envelope(id:UUID().uuidString,senderID:UUID().uuidString,senderName:"test",createdAt:0,kind:"text",text:"你好",files:[])
 let encrypted=try seal(e,key:key);let decoded=try unseal(encrypted,key:key);precondition(decoded.text=="你好");var bad=encrypted;bad[15]^=1;do{_=try unseal(bad,key:key);throw failure("tampering accepted")}catch is CryptoKitError{}
 print("PASS: duplicate naming, path sanitization, retention, protected files, large exclusion, managed-directory scope, AES-GCM roundtrip and tamper rejection")
}
