import AppKit
if CommandLine.arguments.contains("--self-test") {do{try runCoreTests();exit(0)}catch{fputs("FAIL: \(error)\n",stderr);exit(1)}}
let app=NSApplication.shared
if let idx=CommandLine.arguments.firstIndex(of:"--integration-test"),CommandLine.arguments.count>idx+2 {
 let runner=App(),server=CommandLine.arguments[idx+1],temp=URL(fileURLWithPath:CommandLine.arguments[idx+2])
 Task{@MainActor in do{try await runner.integrationTest(server:server,temp:temp);exit(0)}catch{fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}}
 app.run();exit(0)
}
let delegate=App()
app.delegate=delegate
app.setActivationPolicy(.regular)
app.run()
