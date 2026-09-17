import AppKit
import WebKit

let application=NSApplication.shared
application.setActivationPolicy(.accessory)
let runner=App()
let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("ferndrop-memory-"+UUID().uuidString)
func evaluate(_ source:String)async throws->Any? {
 try await withCheckedThrowingContinuation { continuation in
  runner.web.evaluateJavaScript(source){value,error in
   if let error{continuation.resume(throwing:error)}else{continuation.resume(returning:value)}
  }
 }
}
Task{@MainActor in
 do {
  // Isolated support/root: no user history, credentials, network or clipboard access.
  runner.store=try FileStore(support:temporary.appendingPathComponent("support"),initialRoot:temporary.appendingPathComponent("received"))
  let text=String(repeating:"x",count:5000)+"full-text-search-tail"
  runner.store.items=(0..<20_000).map { n in
   var item=Transfer(kind:"text",name:"Fixture \(n)",sender:"Memory test")
   item.id=String(n);item.text=text;return item
  }
  try runner.store.save()
  runner.setupWindow()
  for _ in 0..<100 {
   if (try? await evaluate("typeof window.FernDrop")) as? String=="object" {break}
   try await Task.sleep(nanoseconds:100_000_000)
  }
  for i in 0..<200 {
   runner.used=i
   // Bursts coalesce, even while WebKit is busy. Only one update is in flight.
   for _ in 0..<100{runner.push()}
   try await Task.sleep(nanoseconds:200_000_000)
  }
  let rows=try await evaluate("document.querySelectorAll('#items article').length") as? Int
  guard rows==10 else{throw failure("Expected 10 rows, got \(String(describing:rows))")}
  _=try await runner.handle("setHistoryView",["query":"full-text-search-tail","filter":"all","offset":0])
  try await Task.sleep(nanoseconds:1_000_000_000)
  let last=try await evaluate("document.querySelector('#items article:last-of-type').dataset.id") as? String
  guard last=="9" else{throw failure("Last page was not rendered")}
  for width in [1130.0,880.0] {
   runner.window.setContentSize(NSSize(width:width,height:850))
   for zoom in [1.0,1.5] {
    runner.web.pageZoom=zoom
    try await Task.sleep(nanoseconds:200_000_000)
    let fits=try await evaluate("document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1 && [...document.querySelectorAll('.item-actions')].every(e => e.getBoundingClientRect().right <= document.getElementById('items').getBoundingClientRect().right + 1) && [...document.querySelectorAll('.item-title')].every(e => e.textContent.length <= 160)") as? Bool
    guard fits==true else{throw failure("Horizontal overflow at width \(width), zoom \(zoom)")}
   }
  }
  guard runner.store.items[0].text==text else{throw failure("Original text changed")}
  print("PASS: real WKWebView, 20,000 records, 20,000 push requests, 10 retained/rendered rows, full-text search to final page, originals retained; action buttons visible at 880/1130 widths and 100/150% zoom")
  try? FileManager.default.removeItem(at:temporary)
  exit(0)
 }catch{fputs("FAIL: \(error)\n",stderr);try? FileManager.default.removeItem(at:temporary);exit(1)}
}
application.run()
