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
import CompanionUtilities
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

  /// Short name for the context, recorded as a telemetry normal.
  var telemetryName: String {
    switch self {
    case .simulator: return "simulator"
    case .test: return "test"
    case .app: return "app"
    }
  }

  /// A human-readable label for the report header, naming the bundle or bundle
  /// path the context targets.
  var reportLabel: String {
    switch self {
    case .simulator: return "simulator"
    case let .test(bundle): return "test (`\(bundle.testBundlePath)`)"
    case let .app(app): return "app (`\(app.bundleID)`)"
    }
  }
}

/// A failure while compiling or executing REPL code. Its description is shown to
/// the user and recorded as the telemetry failure message.
enum ReplExecutionError: Error, CustomStringConvertible {
  case compileFailed(String)
  case sessionStopped(String)
  case unexpectedReady
  case streamClosed
  case notReady

  var description: String {
    switch self {
    case let .compileFailed(output):
      return output
    case let .sessionStopped(detail):
      return detail.isEmpty ? "idb_companion ended the REPL session" : detail
    case .unexpectedReady:
      return "idb_companion sent an unexpected 'ready' event instead of a result"
    case .streamClosed:
      return "idb_companion closed the REPL stream without returning a result"
    case .notReady:
      return "idb_companion did not report the REPL as ready"
    }
  }

  /// Whether the REPL session can no longer continue after this error.
  var terminatesSession: Bool {
    switch self {
    case .compileFailed, .unexpectedReady:
      return false
    case .sessionStopped, .streamClosed, .notReady:
      return true
    }
  }
}

/// A failure while retrieving a captured artifact from the companion.
enum ArtifactTransferError: Error, CustomStringConvertible {
  case extractionFailed(String)

  var description: String {
    switch self {
    case let .extractionFailed(path):
      return "Failed to extract the artifact archive at \(path)"
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

  @Option(
    name: .long,
    help: "Connect directly to a companion at host:port (e.g. 127.0.0.1:10882), bypassing discovery. Use to reach an already-running, typically remote, companion.")
  var companion: String?

  @Flag(
    name: .long,
    help: ArgumentHelp(
      "Use an unencrypted TCP connection to the companion instead of TLS.",
      visibility: .hidden))
  var plaintext = false

  @Option(
    name: .long,
    help: "Write a Markdown report of this session (the code run and its results) to this path. If omitted, no report is written.")
  var reportPath: String?

  @Flag(
    name: .long,
    help: "Also record runs whose code fails to compile in the report. Off by default; successful runs and runtime exceptions are always recorded.")
  var reportFailures = false

  @Argument(help: "An optional line of Swift to compile and run once, printing the result to stdout. If omitted, the interactive REPL starts.")
  var code: String?

  func run(context: Context) async throws {
    // @oss-disable

    let reporter = ReplTelemetry.makeReporter()
    var sessionMetadata = [
      "context": context.telemetryName
    ]
    if let udid {
      sessionMetadata["udid"] = udid
    }
    if companion != nil {
      sessionMetadata["connection"] = "remote"
    }
    if let reason = GlobalOptions.shared.reason {
      sessionMetadata["reason"] = reason
    }
    reporter.addMetadata(sessionMetadata)

    // Start a REPL session: connect to the companion and wait for it to report
    // the REPL ready.
    let sessionStart = Date()
    let toolchain: String
    let group: MultiThreadedEventLoopGroup
    let channel: GRPCChannel
    let call: GRPCAsyncBidirectionalStreamingCall<Idb_ReplRequest, Idb_ReplResponse>
    let client: Idb_CompanionServiceAsyncClient
    var responses: GRPCAsyncResponseStream<Idb_ReplResponse>.Iterator
    let deviceType: String
    let osVersion: String
    let nextRunIndex: UInt32
    let sessionID: String
    let autoImportModules: [String]
    let interfaceSearchPaths: [String]
    let sdkPath: String
    let targetTriple: String
    do {
      toolchain = try resolveToolchainPath(explicit: toolchainPath)

      // Resolve the companion to connect to (see `resolveCompanionAddress`): an
      // explicit `--companion host:port`, otherwise a discovered companion.
      let address = try await resolveCompanionAddress()

      group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      channel = try GRPCChannelPool.with(
        target: connectionTarget(for: address),
        transportSecurity: try channelTransportSecurity(
          for: address, tls: plaintext ? .disabled : .metaIdentity),
        eventLoopGroup: group
      )
      client = Idb_CompanionServiceAsyncClient(channel: channel)

      // Create a marker file so the companion can detect whether it shares our
      // filesystem (it checks this path's existence; see Start.probe_file_path).
      let probeFilePath = try sessionDirectory.filePath(named: "shared-fs-probe")
      FileManager.default.createFile(atPath: probeFilePath, contents: Data())

      // Open the bidirectional repl stream and start a session.
      call = client.makeReplCall()
      responses = call.responseStream.makeAsyncIterator()
      try await call.requestStream.send(
        .with {
          $0.control = .start(
            .with {
              $0.context = context.proto
              $0.probeFilePath = probeFilePath
              // Only the test context runs against a bundle; only the app context
              // names an app to launch.
              if case let .test(bundle) = context {
                $0.testBundlePath = bundle.testBundlePath
              }
              if case let .app(app) = context {
                $0.appBundleID = app.bundleID
                $0.reuseSession = app.reuseSession
              }
            })
        })

      // The companion launches the test and connects to the shim before it is ready.
      let first = try await responses.next()
      guard let firstEvent = first?.event, case let .ready(ready) = firstEvent else {
        throw ReplExecutionError.notReady
      }
      deviceType = ready.deviceType
      osVersion = ready.osVersion
      nextRunIndex = ready.nextRunIndex
      sessionID = ready.sessionID
      replSessionInfo.sharedFilesystem = ready.sharedFilesystem
      var readyMetadata = ["device_type": deviceType]
      if !sessionID.isEmpty {
        readyMetadata["session_id"] = sessionID
      }
      reporter.addMetadata(readyMetadata)

      // The companion sends the .swiftinterface files available to injected code
      // (the test bundle's probe-generated modules and the `IDB` module) as
      // contents, since it may not share a filesystem with us. Materialize each into
      // the session directory, add that directory to the compiler's import search
      // path, and auto-import the modules so user code can reference them without an
      // explicit `import`. Report them on stderr (keeping one-shot stdout clean).
      var modules: [String] = []
      var interfaceDirectory: String?
      if !ready.generatedInterfaces.isEmpty {
        FileHandle.standardError.write(Data("idb-repl: received generated interface(s):\n".utf8))
        for interface in ready.generatedInterfaces {
          let path = try sessionDirectory.filePath(named: "\(interface.moduleName).swiftinterface")
          try interface.contents.write(toFile: path, atomically: true, encoding: .utf8)
          interfaceDirectory = (path as NSString).deletingLastPathComponent
          modules.append(interface.moduleName)
          FileHandle.standardError.write(Data("  \(interface.moduleName)\n".utf8))
        }
      }
      autoImportModules = modules
      interfaceSearchPaths = interfaceDirectory.map { [$0] } ?? []

      // The companion reports the connected target's device type and OS version;
      // compile injected code for the matching platform, flooring the deployment
      // target at the runtime OS version so it never links against symbols newer
      // than the runtime provides.
      let platform = try Platform(deviceType: deviceType)
      sdkPath = try resolveSDKPath(platform: platform)
      targetTriple = try resolveTargetTriple(platform: platform, runtimeOSVersion: osVersion)
      FileHandle.standardError.write(Data("idb-repl: compiling injected code for \(targetTriple)\n".utf8))
    } catch {
      reportCall(reporter, "start_session", start: sessionStart, arguments: [], failure: "\(error)")
      throw error
    }
    reportCall(reporter, "start_session", start: sessionStart, arguments: [], failure: nil)

    // Set up the session report if a path was given. Best-effort: failing to open
    // it disables reporting but never stops the REPL.
    var reportWriter: ReplReportWriter?
    if let reportPath {
      let writer = ReplReportWriter(path: reportPath)
      if let resolvedPath = writer.open(
        context: context.reportLabel,
        target: "\(deviceType) \(osVersion)",
        reason: GlobalOptions.shared.reason,
        sessionID: sessionID,
        startedAt: Date())
      {
        FileHandle.standardError.write(Data("idb-repl: writing session report to \(resolvedPath)\n".utf8))
        reportWriter = writer
      }
    }

    // One-shot mode: when a line of code is supplied on the command line, compile
    // and run just that, print the result to stdout, and exit instead of starting
    // the interactive REPL.
    if let code {
      let start = Date()
      do {
        let index = Int(nextRunIndex)
        let dylib = try compileRun(swiftCode: code, index: index, interfaceSearchPaths: interfaceSearchPaths, autoImportModules: autoImportModules, targetTriple: targetTriple, sdkPath: sdkPath, toolchain: toolchain)
        try await call.requestStream.send(
          .with {
            $0.control = .execute(
              .with {
                $0.dylib = dylib
                $0.symbol = "idb_repl_\(index)"
              })
          })
        switch try await responses.next()?.event {
        case let .result(result):
          print(result.output)
          let artifactFilenames = await transferArtifacts(result.artifacts, client: client, into: reportWriter)
          reportWriter?.recordRun(index: index, code: code, output: result.output, artifactFilenames: artifactFilenames, at: Date())
        case let .stopped(stopped):
          throw ReplExecutionError.sessionStopped(stopped.desc)
        case .ready:
          throw ReplExecutionError.unexpectedReady
        case .none:
          throw ReplExecutionError.streamClosed
        }
        reportCall(reporter, "run", start: start, arguments: codeMetadata(code), failure: nil)
      } catch {
        print("Error: \(error)")
        if reportFailures, case let ReplExecutionError.compileFailed(compilerOutput) = error {
          reportWriter?.recordCompileFailure(code: code, compilerOutput: compilerOutput, at: Date())
        }
        reportCall(reporter, "run", start: start, arguments: codeMetadata(code), failure: "\(error)")
      }

      reportWriter?.close()
      try? await call.requestStream.finish()
      try? await channel.close().get()
      try? await group.shutdownGracefully()
      sessionDirectory.cleanup()
      return
    }

    printStatus("Connected to \(deviceType) \(osVersion) process.", "Type '/help' for available commands.")

    var lines: [String] = []
    let editor = LineEditor()
    var runIndex = Int(nextRunIndex)

    inputLoop: while let input = editor.readLine() {
      let trimmed = input.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }

      if trimmed.hasPrefix("/") {
        print("")
        switch trimmed {
        case "/run":
          let start = Date()
          let swiftCode = lines.joined(separator: "\n")
          var stopSession = false
          do {
            let dylib = try compileRun(swiftCode: swiftCode, index: runIndex, interfaceSearchPaths: interfaceSearchPaths, autoImportModules: autoImportModules, targetTriple: targetTriple, sdkPath: sdkPath, toolchain: toolchain)
            try await call.requestStream.send(
              .with {
                $0.control = .execute(
                  .with {
                    $0.dylib = dylib
                    $0.symbol = "idb_repl_\(runIndex)"
                  })
              })
            switch try await responses.next()?.event {
            case let .result(result):
              printStatus(result.output)
              let artifactFilenames = await transferArtifacts(result.artifacts, client: client, into: reportWriter)
              reportWriter?.recordRun(index: runIndex, code: swiftCode, output: result.output, artifactFilenames: artifactFilenames, at: Date())
              runIndex = result.nextRunIndex >= 0 ? Int(result.nextRunIndex) : 0
            case let .stopped(stopped):
              throw ReplExecutionError.sessionStopped(stopped.desc)
            case .ready:
              throw ReplExecutionError.unexpectedReady
            case .none:
              throw ReplExecutionError.streamClosed
            }
            reportCall(reporter, "run", start: start, arguments: codeMetadata(swiftCode), failure: nil)
          } catch {
            printStatus("Error:", "\(error)")
            if reportFailures, case let ReplExecutionError.compileFailed(compilerOutput) = error {
              reportWriter?.recordCompileFailure(code: swiftCode, compilerOutput: compilerOutput, at: Date())
            }
            reportCall(reporter, "run", start: start, arguments: codeMetadata(swiftCode), failure: "\(error)")
            stopSession = (error as? ReplExecutionError)?.terminatesSession ?? true
          }
          lines = []
          if stopSession {
            break inputLoop
          }
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

    reportWriter?.close()
    try? await call.requestStream.finish()
    try? await channel.close().get()
    try? await group.shutdownGracefully()
    sessionDirectory.cleanup()
  }

  /// Resolves the companion address to connect to. `--companion host:port`
  /// connects directly to an explicit (typically remote) TCP companion, bypassing
  /// discovery, matching idb-forward. Otherwise a companion is discovered — by
  /// `--udid`, or the single running / only-available-simulator default — and
  /// started if needed, exiting after 5 minutes without gRPC activity so it does
  /// not outlive its use.
  private func resolveCompanionAddress() async throws -> CompanionAddress {
    if let companion {
      guard let address = CompanionAddress.parse(tcp: companion) else {
        throw ValidationError(
          "--companion expects host:port, e.g. 127.0.0.1:10882 (got '\(companion)')")
      }
      return address
    }
    let idleShutdownTime = 5 * 60
    if let udid {
      return try await companionManager()
        .companionInfo(forUDID: udid, idleShutdownTime: idleShutdownTime).address
    }
    return try await companionManager()
      .defaultCompanion(idleShutdownTime: idleShutdownTime).address
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

  /// Compiles the entered Swift into a dylib and returns its bytes, throwing
  /// `ReplExecutionError.compileFailed` (carrying the compiler output) when the
  /// compile fails.
  private func compileRun(swiftCode: String, index: Int, interfaceSearchPaths: [String], autoImportModules: [String], targetTriple: String, sdkPath: String, toolchain: String) throws -> Data {
    let swiftPath = try sessionDirectory.filePath(named: "run-\(index).swift")
    let dylibPath = try sessionDirectory.filePath(named: "run-\(index).dylib")

    let code = ReplSourceGenerator.generateSource(for: swiftCode, index: index, autoImportModules: autoImportModules)
    try code.write(toFile: swiftPath, atomically: true, encoding: .utf8)

    let (status, compilerOutput) = try compileSwift(sourcePath: swiftPath, outputPath: dylibPath, index: index, interfaceSearchPaths: interfaceSearchPaths, targetTriple: targetTriple, sdkPath: sdkPath, toolchain: toolchain)
    try? FileManager.default.removeItem(atPath: swiftPath)

    guard status == 0 else {
      throw ReplExecutionError.compileFailed(compilerOutput)
    }
    return try Data(contentsOf: URL(fileURLWithPath: dylibPath))
  }

  private func compileSwift(sourcePath: String, outputPath: String, index: Int, interfaceSearchPaths: [String], targetTriple: String, sdkPath: String, toolchain: String) throws -> (Int32, String) {
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
      // Give each submission a unique, predictable module name matching its
      // entry-point symbol.
      "-module-name", "idb_repl_\(index)",
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

  /// Coarse telemetry metadata describing a block of code — its character count
  /// and its significant line count — as `key=value` elements for a call's
  /// `arguments`.
  private func codeMetadata(_ code: String) -> [String] {
    [
      "size=\(code.count)",
      "lines=\(ReplSourceMetadata.countSignificantLinesOfCode(in: code))",
    ]
  }

  /// Reports the outcome of a timed call (`nil` failure means success).
  private func reportCall(_ reporter: FBEventReporter, _ name: String, start: Date, arguments: [String], failure: String?) {
    let duration = Date().timeIntervalSince(start)
    if let failure {
      reporter.report(FBEventReporterSubject(forFailingCall: name, duration: duration, message: failure, size: nil, arguments: arguments))
    } else {
      reporter.report(FBEventReporterSubject(forSuccessfulCall: name, duration: duration, size: nil, arguments: arguments))
    }
  }

  private func printStatus(_ lines: String...) {
    for line in lines {
      print(line)
    }
    print("")
  }

  /// Retrieves each artifact captured during a run and returns the filenames stored
  /// beside the session report (empty when no report is being written). Artifacts are
  /// stored next to the report — in its `artifactsDirectory()` — so the report can
  /// link them and they persist; without a report they land in the ephemeral session
  /// directory instead. When the companion shares our filesystem the file is moved
  /// directly; otherwise it is pulled over gRPC (the AUXILLARY container) and removed
  /// from the companion. Best-effort: failing to retrieve one artifact is logged and
  /// does not stop the session.
  private func transferArtifacts(_ artifacts: [Idb_ReplResponse.Result.Artifact], client: Idb_CompanionServiceAsyncClient, into reportWriter: ReplReportWriter?) async -> [String] {
    guard !artifacts.isEmpty else {
      return []
    }

    // Prefer the report's artifacts directory (persistent and linkable); fall back to
    // the ephemeral session directory when there is no report.
    let reportArtifactsDirectory = reportWriter?.artifactsDirectory()
    let directory: String
    if let reportArtifactsDirectory {
      directory = reportArtifactsDirectory
    } else if let sessionArtifacts = try? sessionDirectory.artifactsDirectory() {
      directory = sessionArtifacts
    } else {
      FileHandle.standardError.write(Data("idb-repl: could not prepare an artifacts directory\n".utf8))
      return []
    }
    // Only files stored beside the report can be linked from it.
    let linkable = reportArtifactsDirectory != nil

    var filenames: [String] = []
    for artifact in artifacts {
      do {
        let localPath: String
        if replSessionInfo.sharedFilesystem {
          localPath = try moveArtifact(hostPath: artifact.hostPath, into: directory)
        } else {
          localPath = try await pullArtifact(containerPath: artifact.containerPath, client: client, into: directory)
        }
        FileHandle.standardError.write(Data("idb-repl: saved artifact to \(localPath)\n".utf8))
        if linkable {
          filenames.append((localPath as NSString).lastPathComponent)
        }
      } catch {
        FileHandle.standardError.write(Data("idb-repl: could not retrieve artifact \(artifact.hostPath): \(error)\n".utf8))
      }
    }
    return filenames
  }

  /// Moves a companion-written artifact (visible because we share the filesystem)
  /// into `directory`.
  private func moveArtifact(hostPath: String, into directory: String) throws -> String {
    let destination = (directory as NSString).appendingPathComponent((hostPath as NSString).lastPathComponent)
    try? FileManager.default.removeItem(atPath: destination)
    try FileManager.default.moveItem(atPath: hostPath, toPath: destination)
    return destination
  }

  /// Pulls an artifact from the companion's AUXILLARY container (streamed back as a
  /// gzipped tar), extracts it into `directory`, and removes the companion copy.
  private func pullArtifact(containerPath: String, client: Idb_CompanionServiceAsyncClient, into directory: String) async throws -> String {
    let request = Idb_PullRequest.with {
      $0.srcPath = containerPath
      $0.dstPath = "" // empty: stream the bytes back rather than copy them host-side
      $0.container = .with { $0.kind = .auxillary }
    }
    var archive = Data()
    for try await response in client.pull(request) {
      archive.append(response.payload.data)
    }

    let name = (containerPath as NSString).lastPathComponent
    let destination = (directory as NSString).appendingPathComponent(name)
    let archivePath = (directory as NSString).appendingPathComponent(name + ".tar.gz")
    try archive.write(to: URL(fileURLWithPath: archivePath))
    defer { try? FileManager.default.removeItem(atPath: archivePath) }
    try Self.extractArchive(at: archivePath, into: directory)

    _ = try? await client.rm(
      Idb_RmRequest.with {
        $0.paths = [containerPath]
        $0.container = .with { $0.kind = .auxillary }
      })
    return destination
  }

  private static func extractArchive(at archivePath: String, into directory: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = ["-xzf", archivePath, "-C", directory]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw ArtifactTransferError.extractionFailed(archivePath)
    }
  }
}
