/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// patternlint-disable cdecl-unsupported
// patternlint-disable avoid-print-to-prevent-production-overhead

import ArgumentParser
import CompanionDiscovery
import Foundation
import GRPC
import IDBGRPCSwift
import NIOCore
import NIOPosix

/// Selects which context the REPL runs in. The `test` and `app` contexts carry
/// the options they need; `simulator` has none.
enum Context {
  case simulator
  case test(TestBundleOptions)
  case app(AppOptions)

  /// The corresponding gRPC enum forwarded to the companion in the Start message.
  var proto: Idb_ReplRequest.Start.Context {
    switch self {
    case .simulator: return .simulator
    case .test: return .test
    case .app: return .app
    }
  }
}

/// Shared REPL implementation backing both the `test` and `simulator`
/// subcommands. Its options are flattened into each subcommand via `@OptionGroup`.
struct ReplRunner: ParsableArguments {
  @Option(
    name: .long,
    help: "UDID of the simulator to use for execution. If omitted, the single running companion is used, or one is started for the only available simulator.")
  var udid: String?

  @Option(name: .long, help: "Path to the Swift toolchain used to compile code. Defaults to the selected Xcode toolchain (xcode-select -p).")
  var toolchainPath: String?

  @Option(
    name: .long,
    help: ArgumentHelp(
      "Path to the idb_companion binary, overriding the default system installed binary.",
      visibility: .hidden))
  var idbCompanionBinary: String?

  @Argument(help: "An optional line of Swift to compile and run once, printing the result to stdout. If omitted, the interactive REPL starts.")
  var code: String?

  func run(context: Context) async throws {
    let toolchain = try resolveToolchainPath(explicit: toolchainPath)

    // Discover the companion to use, starting one if needed. A companion we start
    // should not outlive its use, so it exits after 5 minutes without gRPC
    // activity. With no udid, use the single running companion (or start one for
    // the only available simulator).
    let idleShutdownTime = 5 * 60
    let companion: CompanionInfo
    if let udid {
      companion = try await companionManager().companionInfo(forUDID: udid, idleShutdownTime: idleShutdownTime)
    } else {
      companion = try await companionManager().defaultCompanion(idleShutdownTime: idleShutdownTime)
    }

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let channel = try GRPCChannelPool.with(
      target: connectionTarget(for: companion.address),
      transportSecurity: .plaintext,
      eventLoopGroup: group
    )
    let client = Idb_CompanionServiceAsyncClient(channel: channel)

    // Open the bidirectional repl stream and start a session.
    let call = client.makeReplCall()
    var responses = call.responseStream.makeAsyncIterator()
    try await call.requestStream.send(
      .with {
        $0.control = .start(
          .with {
            $0.context = context.proto
            // Only the test context runs against a bundle; only the app context
            // names an app to launch.
            if case let .test(bundle) = context {
              $0.testBundlePath = bundle.testBundlePath
            }
            if case let .app(app) = context {
              $0.appBundleID = app.bundleID
            }
          })
      })

    // The companion launches the test and connects to the shim before it is ready.
    let first = try await responses.next()
    guard let firstEvent = first?.event, case let .ready(ready) = firstEvent else {
      throw ValidationError("idb_companion did not report the REPL as ready")
    }

    // The companion sends the .swiftinterface files available to injected code
    // (the test bundle's probe-generated modules and the `IDB` module) as
    // contents, since it may not share a filesystem with us. Materialize each into
    // the session directory, add that directory to the compiler's import search
    // path, and auto-import the modules so user code can reference them without an
    // explicit `import`. Report them on stderr (keeping one-shot stdout clean).
    var autoImportModules: [String] = []
    var interfaceDirectory: String?
    if !ready.generatedInterfaces.isEmpty {
      FileHandle.standardError.write(Data("idb-repl: received generated interface(s):\n".utf8))
      for interface in ready.generatedInterfaces {
        let path = try sessionDirectory.filePath(named: "\(interface.moduleName).swiftinterface")
        try interface.contents.write(toFile: path, atomically: true, encoding: .utf8)
        interfaceDirectory = (path as NSString).deletingLastPathComponent
        autoImportModules.append(interface.moduleName)
        FileHandle.standardError.write(Data("  \(interface.moduleName)\n".utf8))
      }
    }
    let interfaceSearchPaths = interfaceDirectory.map { [$0] } ?? []

    // The companion reports the connected target's device type; compile injected
    // code for the matching platform.
    let platform = try Platform(deviceType: ready.deviceType)
    let sdkPath = try resolveSDKPath(platform: platform)
    let targetTriple = try resolveTargetTriple(platform: platform)

    // One-shot mode: when a line of code is supplied on the command line, compile
    // and run just that, print the result to stdout, and exit instead of starting
    // the interactive REPL.
    if let code {
      do {
        if let dylib = compileRun(swiftCode: code, index: 0, interfaceSearchPaths: interfaceSearchPaths, autoImportModules: autoImportModules, targetTriple: targetTriple, sdkPath: sdkPath, toolchain: toolchain) {
          try await call.requestStream.send(
            .with {
              $0.control = .execute(
                .with {
                  $0.dylib = dylib
                  $0.symbol = "idb_repl_0"
                })
            })
          switch try await responses.next()?.event {
          case let .result(result):
            print(result.output)
          case let .stopped(stopped):
            print(stopped.desc.isEmpty ? "idb_companion ended the REPL session" : stopped.desc)
          case .ready:
            print("Error: idb_companion sent an unexpected 'ready' event instead of a result")
          case .none:
            print("Error: idb_companion closed the REPL stream without returning a result")
          }
        }
      } catch let status as GRPCStatus {
        print("Error: \(status.message ?? "idb_companion failed with gRPC status \(status.code)")")
      } catch {
        print("Error: \(error)")
      }

      try? await call.requestStream.finish()
      try? await channel.close().get()
      try? await group.shutdownGracefully()
      sessionDirectory.cleanup()
      return
    }

    printStatus("Connected to \(ready.deviceType) process.", "Type '/help' for available commands.")

    var lines: [String] = []
    let editor = LineEditor()
    var runIndex = 0

    inputLoop: while let input = editor.readLine() {
      let trimmed = input.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }

      if trimmed.hasPrefix("/") {
        print("")
        switch trimmed {
        case "/run":
          let swiftCode = lines.joined(separator: "\n")
          if let dylib = compileRun(swiftCode: swiftCode, index: runIndex, interfaceSearchPaths: interfaceSearchPaths, autoImportModules: autoImportModules, targetTriple: targetTriple, sdkPath: sdkPath, toolchain: toolchain) {
            try await call.requestStream.send(
              .with {
                $0.control = .execute(
                  .with {
                    $0.dylib = dylib
                    $0.symbol = "idb_repl_\(runIndex)"
                  })
              })
            do {
              let event = try await responses.next()?.event
              switch event {
              case let .result(result):
                printStatus(result.output)
              case let .stopped(stopped):
                let detail = stopped.desc.isEmpty ? "idb_companion ended the REPL session" : stopped.desc
                printStatus("Session ended:", detail)
                break inputLoop
              case .ready:
                printStatus("Error:", "idb_companion sent an unexpected 'ready' event instead of a result")
              case .none:
                printStatus("Error:", "idb_companion closed the REPL stream without returning a result")
                break inputLoop
              }
            } catch let status as GRPCStatus {
              printStatus("Error:", status.message ?? "idb_companion failed with gRPC status \(status.code)")
              break inputLoop
            } catch {
              printStatus("Error:", "\(error)")
              break inputLoop
            }
          }
          runIndex += 1
          lines = []
        case "/help":
          printHelp()
        case "/exit":
          break inputLoop
        default:
          printStatus("Unknown command: '\(trimmed)'. Type '/help' for available commands.")
        }
      } else {
        lines.append(input)
      }
    }

    try? await call.requestStream.finish()
    try? await channel.close().get()
    try? await group.shutdownGracefully()
    sessionDirectory.cleanup()
  }

  private func companionManager() -> CompanionManager {
    if let idbCompanionBinary {
      return CompanionManager(companionPath: idbCompanionBinary)
    }
    return CompanionManager()
  }

  /// Maps a discovered companion's address to a connection target.
  private func connectionTarget(for address: CompanionAddress) -> ConnectionTarget {
    switch address {
    case let .domainSocket(path):
      return .unixDomainSocket(path)
    case let .tcp(host, port):
      return .hostAndPort(host, port)
    }
  }

  /// Compiles the entered Swift into a dylib and returns its bytes, or prints a
  /// compile error and returns nil.
  private func compileRun(swiftCode: String, index: Int, interfaceSearchPaths: [String], autoImportModules: [String], targetTriple: String, sdkPath: String, toolchain: String) -> Data? {
    do {
      let swiftPath = try sessionDirectory.filePath(named: "run-\(index).swift")
      let dylibPath = try sessionDirectory.filePath(named: "run-\(index).dylib")

      let code = ReplSourceGenerator.generateSource(for: swiftCode, index: index, autoImportModules: autoImportModules)
      try code.write(toFile: swiftPath, atomically: true, encoding: .utf8)

      let (status, compilerOutput) = try compileSwift(sourcePath: swiftPath, outputPath: dylibPath, interfaceSearchPaths: interfaceSearchPaths, targetTriple: targetTriple, sdkPath: sdkPath, toolchain: toolchain)
      try? FileManager.default.removeItem(atPath: swiftPath)

      if status == 0 {
        return try Data(contentsOf: URL(fileURLWithPath: dylibPath))
      } else {
        printStatus("Error:", compilerOutput)
        return nil
      }
    } catch {
      printStatus("Error:", "\(error)")
      return nil
    }
  }

  private func compileSwift(sourcePath: String, outputPath: String, interfaceSearchPaths: [String], targetTriple: String, sdkPath: String, toolchain: String) throws -> (Int32, String) {
    let swiftcPath = (toolchain as NSString).appendingPathComponent("usr/bin/swiftc")
    let swiftc = Process()
    swiftc.executableURL = URL(fileURLWithPath: swiftcPath)
    var environment = ProcessInfo.processInfo.environment
    environment["SDKROOT"] = sdkPath
    swiftc.environment = environment
    var arguments = [
      sourcePath,
      "-emit-library", "-o", outputPath,
      "-target", targetTriple,
    ]
    // Add the probe-generated .swiftinterface directories to the import search
    // path so injected code can `import` the test bundle's modules. The symbols
    // themselves are resolved at load time via `-undefined dynamic_lookup`.
    for searchPath in interfaceSearchPaths {
      arguments.append(contentsOf: ["-I", searchPath])
    }
    arguments.append(contentsOf: ["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"])
    swiftc.arguments = arguments
    let outputPipe = Pipe()
    swiftc.standardOutput = outputPipe
    let errorPipe = Pipe()
    swiftc.standardError = errorPipe
    try swiftc.run()

    // Read both pipes concurrently to avoid deadlock when the OS pipe buffer fills.
    var outputData = Data()
    var errorData = Data()
    let group = DispatchGroup()

    group.enter()
    DispatchQueue.global().async {
      outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
      group.leave()
    }

    group.enter()
    DispatchQueue.global().async {
      errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      group.leave()
    }

    group.wait()
    swiftc.waitUntilExit()

    let filters: [NSRegularExpression] = [
      try NSRegularExpression(pattern: #"ld: warning: -undefined dynamic_lookup is deprecated.*"#)
    ]

    let sessionPath = sessionDirectory.path
    var filteredLines: [String] = []

    for data in [outputData, errorData] {
      if let output = String(data: data, encoding: .utf8) {
        for line in output.components(separatedBy: "\n") {
          let range = NSRange(line.startIndex..., in: line)
          let filtered = filters.contains { $0.firstMatch(in: line, range: range) != nil }
          if !filtered && !line.isEmpty && !line.contains("// idb-repl-strip") {
            filteredLines.append(line.replacingOccurrences(of: sessionPath, with: ""))
          }
        }
      }
    }

    return (swiftc.terminationStatus, filteredLines.joined(separator: "\n"))
  }

  private func printHelp() {
    printStatus(
      "Available commands:",
      "  /help         Show this help message",
      "  /run          Compile and inject the entered Swift code",
      "  /exit         Kill subprocesses and exit",
      "",
      "Enter Swift code line by line, then type /run to execute."
    )
  }

  private func printStatus(_ lines: String...) {
    for line in lines {
      print(line)
    }
    print("")
  }
}
