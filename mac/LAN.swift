import Foundation
import Network
// Bonjour supplies candidates, never trust. Successful authenticated decrypt + encrypted ack proves pairing.
final class LAN:NSObject,NetServiceDelegate {
 var listener:NWListener?;var browser:NWBrowser?;var candidates:[NWEndpoint]=[]
 var services:[String:NetService]=[:];var resolvedAddresses:[String:[NWEndpoint]]=[:]
 var onReceive:((Data)->Data?)?;var onPeers:(([String])->Void)?
 func start(name:String)throws {
  let l=try NWListener(using:.tcp,on:.any);l.service=NWListener.Service(name:name,type:"_ferndrop._tcp");l.newConnectionHandler={[weak self] c in self?.receive(c)};l.start(queue:.main);listener=l
  let b=NWBrowser(for:.bonjour(type:"_ferndrop._tcp",domain:nil),using:.tcp)
  b.browseResultsChangedHandler={[weak self] results,_ in guard let self else{return};self.candidates=results.map(\.endpoint).filter{ep in if case let .service(n,_,_,_)=ep{return n != name};return false};self.resolveCandidates();self.onPeers?(self.candidates.map{if case let .service(n,_,_,_)=$0{return n};return "局域网设备"})}
  b.start(queue:.main);browser=b
 }
 func resolveCandidates(){
  let names=Set(candidates.compactMap{ep->String? in if case let .service(n,_,_,_)=ep{return n};return nil})
  for name in Array(services.keys) where !names.contains(name){services.removeValue(forKey:name)?.stop();resolvedAddresses.removeValue(forKey:name)}
  for endpoint in candidates {if case let .service(name,type,domain,_)=endpoint,services[name]==nil {
   let service=NetService(domain:domain,type:type,name:name);service.delegate=self;services[name]=service;service.resolve(withTimeout:5)
  }}
 }
 func netServiceDidResolveAddress(_ sender:NetService){
  guard sender.port>0,let port=NWEndpoint.Port(rawValue:UInt16(sender.port)) else{return}
  resolvedAddresses[sender.name]=(sender.addresses ?? []).compactMap{data in
   data.withUnsafeBytes{raw->NWEndpoint? in guard let base=raw.baseAddress else{return nil};let address=base.assumingMemoryBound(to:sockaddr.self)
    var host=[CChar](repeating:0,count:Int(NI_MAXHOST))
    guard getnameinfo(address,socklen_t(data.count),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST)==0 else{return nil}
    return .hostPort(host:NWEndpoint.Host(String(cString:host)),port:port)
   }
  }
 }
 func netService(_ sender:NetService,didNotResolve errorDict:[String:NSNumber]){services.removeValue(forKey:sender.name);resolvedAddresses.removeValue(forKey:sender.name)}
 func receive(_ c:NWConnection){c.start(queue:.main);readFrame(c,limit:28_000_000){[weak self] data in guard let data,let ack=self?.onReceive?(data) else{c.cancel();return};self?.writeFrame(c,ack){c.cancel()}}}
 func writeFrame(_ c:NWConnection,_ data:Data,done:@escaping()->Void){var length=UInt32(data.count).bigEndian;var packet=Data(bytes:&length,count:4);packet.append(data);c.send(content:packet,completion:.contentProcessed{_ in done()})}
 func readFrame(_ c:NWConnection,limit:Int,done:@escaping(Data?)->Void){
  var buffer=Data(),expected:Int?
  var finished=false;let deadline=DispatchWorkItem{if !finished{finished=true;c.cancel();done(nil)}};DispatchQueue.main.asyncAfter(deadline:.now()+30,execute:deadline)
  func read(){c.receive(minimumIncompleteLength:1,maximumLength:64*1024){data,_,complete,error in
   guard !finished else{return};if let data{buffer.append(data)}
   if expected==nil && buffer.count>=4{expected=buffer.prefix(4).reduce(0){($0<<8)|Int($1)};buffer.removeFirst(4);if expected!<1||expected!>limit{finished=true;deadline.cancel();done(nil);return}}
   if let n=expected,buffer.count>=n{finished=true;deadline.cancel();done(Data(buffer.prefix(n)));return}
   if complete||error != nil{finished=true;deadline.cancel();done(nil)}else{read()}
  }};read()
 }
 func send(_ data:Data,validate:@escaping(Data)->Bool)async->Bool {
  resolveCandidates()
  let endpoints=Array(Set(candidates.flatMap{ep->[NWEndpoint] in if case let .service(n,_,_,_)=ep,let addresses=resolvedAddresses[n],!addresses.isEmpty{return addresses};return [ep]}).prefix(32))
  guard !endpoints.isEmpty else{return false}
  return await withCheckedContinuation { continuation in
   let connections=endpoints.map{NWConnection(to:$0,using:.tcp)};var finished=false,remaining=connections.count
   let deadline=DispatchWorkItem{if !finished{finished=true;connections.forEach{$0.stateUpdateHandler=nil;$0.cancel()};continuation.resume(returning:false)}}
   func finish(_ ok:Bool){guard !finished else{return};remaining-=1;if ok||remaining==0{finished=true;deadline.cancel();connections.forEach{$0.stateUpdateHandler=nil;$0.cancel()};continuation.resume(returning:ok)}}
   DispatchQueue.main.asyncAfter(deadline:.now()+5,execute:deadline)
   for c in connections {var settled=false
    func result(_ ok:Bool){guard !settled else{return};settled=true;finish(ok)}
    c.stateUpdateHandler={[weak self] state in guard !finished else{return};if case .ready=state {self?.writeFrame(c,data){self?.readFrame(c,limit:10000){ack in result(ack.map(validate) ?? false)}}}else if case .failed=state{result(false)}};c.start(queue:.main)
   }
  }
 }
}
