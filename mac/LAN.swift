import Foundation
import Network
// Bonjour supplies candidates, never trust. Successful authenticated decrypt + encrypted ack proves pairing.
final class LAN {
 var listener:NWListener?;var browser:NWBrowser?;var candidates:[NWEndpoint]=[]
 var onReceive:((Data)->Data?)?;var onPeers:(([String])->Void)?
 func start(name:String)throws {
  let l=try NWListener(using:.tcp,on:.any);l.service=NWListener.Service(name:name,type:"_ferndrop._tcp");l.newConnectionHandler={[weak self] c in self?.receive(c)};l.start(queue:.main);listener=l
  let b=NWBrowser(for:.bonjour(type:"_ferndrop._tcp",domain:nil),using:.tcp)
  b.browseResultsChangedHandler={[weak self] results,_ in guard let self else{return};self.candidates=results.map(\.endpoint).filter{ep in if case let .service(n,_,_,_)=ep{return n != name};return false};self.onPeers?(self.candidates.map{if case let .service(n,_,_,_)=$0{return n};return "局域网设备"})}
  b.start(queue:.main);browser=b
 }
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
  for endpoint in candidates {
   let ok:Bool=await withCheckedContinuation { continuation in
    let c=NWConnection(to:endpoint,using:.tcp);var resolved=false
    func finish(_ ok:Bool){if !resolved{resolved=true;c.cancel();continuation.resume(returning:ok)}}
    DispatchQueue.main.asyncAfter(deadline:.now()+3){finish(false)}
    c.stateUpdateHandler={[weak self] state in if case .ready=state {self?.writeFrame(c,data){self?.readFrame(c,limit:10000){ack in finish(ack.map(validate) ?? false)}}}else if case .failed=state{finish(false)}};c.start(queue:.main)
   }
   if ok{return true}
  };return false
 }
}
