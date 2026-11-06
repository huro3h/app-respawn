// app-respawn-launcher
//   LaunchAgent が最初に起動する入口。引数のコマンド(ruby app-respawn --watch ...)を子として起動し、
//   その終了コードで終わる。
//
//   TCC(自動化・アクセシビリティ)は launchd ジョブの先頭のプロセスを責任プロセスとして判定するので、
//   許可はこのバイナリに付く。ruby を先頭にすると、ad-hoc 署名の識別子がバイナリのハッシュ(cdhash)のため、
//   Ruby を上げるたびに許可が切れる。これを挟めば ruby は rbenv の shim 経由で差し替えられる。
//
//   setup がビルドする。作り直してもハッシュが変わって許可が切れるので、ソースが変わったときだけビルドする。

import Foundation

let command = Array(CommandLine.arguments.dropFirst())
guard !command.isEmpty else {
  FileHandle.standardError.write("usage: app-respawn-launcher <command> [args...]\n".data(using: .utf8)!)
  exit(2)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: command[0])
process.arguments = Array(command.dropFirst())
process.terminationHandler = { p in
  // シグナルで終わったときはシェルと同じく 128 + シグナル番号にする
  exit(p.terminationReason == .uncaughtSignal ? 128 + p.terminationStatus : p.terminationStatus)
}

do {
  try process.run()
} catch {
  FileHandle.standardError.write("app-respawn-launcher: \(command[0]) を実行できません: \(error)\n".data(using: .utf8)!)
  exit(2)
}

// launchctl bootout / kickstart -k の SIGTERM を子へ渡す。無視の設定は子が受け継がないよう起動の後に行う
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
  signal(sig, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
  source.setEventHandler { if process.isRunning { kill(process.processIdentifier, sig) } }
  source.resume()
  signalSources.append(source)
}

dispatchMain()
