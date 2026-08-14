/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import ArgumentParser
import CompanionDiscovery
import CompanionUtilities
import Foundation
import GRPC
import IDBGRPCSwift
import NIOCore
import NIOPosix
import ReplCompiler

/// The options needed to establish a REPL session, gathered from the CLI so both
/// `ReplRunner` (the interactive/one-shot subcommands) and `ReplayCommand` can drive a
/// `ReplSession` the same way.
struct ReplSessionConfig {
  var udid: String?
  var toolchainPath: String?
  var idbCompanionBinary: String?
  var companion: String?
  var plaintext: Bool
  var reportPath: String?
  var reportFailures: Bool
  var reason: String?
  var mode: ReplSessionMode = .interactive
}

/// The outcome of executing one block of code: the output the target returned (already
/// prefixed `Result:` or `Exception:`), the next run index the companion reported
/// (negative once the session has ended), and the filenames of any artifacts captured
/// during the run (empty unless a report is being written).
struct ExecutionResult {
  var output: String
  var nextIndex: Int
  var artifactFilenames: [String]
}

/// A live REPL session against a companion: it owns the gRPC stream and the compile
/// parameters, executes blocks of code against the connected target, and (when a report
/// path is configured) records each run. Created by `start`, driven by `execute`, and
/// torn down by `finish`. Used sequentially from a single task, so it is a plain
/// (non-Sendable) reference type.
final class ReplSession {

  /// The connected target's device type (e.g. `iphone`), reported at handshake.
  let deviceType: String
  /// The connected target's runtime OS version, reported at handshake.
  let osVersion: String
  /// The companion's id for this REPL session (empty when the companion reports none).
  let sessionID: String
  /// Whether the app was freshly launched at this session's start (app context only;
  /// false otherwise). `replay` reproduces this to start from the same state.
  let freshLaunch: Bool
  /// The index the next executed block will use; advanced after each completed run.
  private(set) var nextRunIndex: Int

  private let config: ReplSessionConfig
  private let reporter: FBEventReporter
  /// When the session began connecting; the `session_end` event's duration
  /// measures from here.
  private let startedAt: Date
  /// How many blocks this session attempted to execute (successes and
  /// failures alike); reported on the `session_end` event.
  private var runsExecuted = 0
  private let group: MultiThreadedEventLoopGroup
  private let channel: GRPCChannel
  private let call: GRPCAsyncBidirectionalStreamingCall<Idb_ReplRequest, Idb_ReplResponse>
  private let client: Idb_CompanionServiceAsyncClient
  private var responses: GRPCAsyncResponseStream<Idb_ReplResponse>.Iterator
  private let toolchain: String
  private let targetTriple: String
  private let sdkPath: String
  private let compilerArguments: [String]
  private let linkerArguments: [String]
  private let interfaceSearchPaths: [String]
  private let autoImportModules: [String]
  private let reportWriter: ReplReportWriter?

  private init(
    config: ReplSessionConfig,
    reporter: FBEventReporter,
    startedAt: Date,
    group: MultiThreadedEventLoopGroup,
    channel: GRPCChannel,
    call: GRPCAsyncBidirectionalStreamingCall<Idb_ReplRequest, Idb_ReplResponse>,
    client: Idb_CompanionServiceAsyncClient,
    responses: GRPCAsyncResponseStream<Idb_ReplResponse>.Iterator,
    deviceType: String,
    osVersion: String,
    sessionID: String,
    freshLaunch: Bool,
    nextRunIndex: Int,
    toolchain: String,
    targetTriple: String,
    sdkPath: String,
    compilerArguments: [String],
    linkerArguments: [String],
    interfaceSearchPaths: [String],
    autoImportModules: [String],
    reportWriter: ReplReportWriter?
  ) {
    self.config = config
    self.reporter = reporter
    self.startedAt = startedAt
    self.group = group
    self.channel = channel
    self.call = call
    self.client = client
    self.responses = responses
    self.deviceType = deviceType
    self.osVersion = osVersion
    self.sessionID = sessionID
    self.freshLaunch = freshLaunch
    self.nextRunIndex = nextRunIndex
    self.toolchain = toolchain
    self.targetTriple = targetTriple
    self.sdkPath = sdkPath
    self.compilerArguments = compilerArguments
    self.linkerArguments = linkerArguments
    self.interfaceSearchPaths = interfaceSearchPaths
    self.autoImportModules = autoImportModules
    self.reportWriter = reportWriter
  }

  /// Starts a REPL session: connects to the companion (an explicit `--companion` or a
  /// discovered one), opens the bidirectional `repl` stream, sends the Start message for
  /// `context`, waits for the companion to report the REPL ready, materializes the
  /// generated `.swiftinterface` files, resolves the compile platform, and — when a
  /// report path is configured — opens the session report.
  static func start(context: Context, config: ReplSessionConfig) async throws -> ReplSession {
    // @oss-disable

    let reporter = ReplTelemetry.makeReporter()
    var sessionMetadata = [
      "context": context.telemetryName,
      "mode": config.mode.rawValue,
    ]
    if let udid = config.udid {
      sessionMetadata["udid"] = udid
    }
    if config.companion != nil {
      sessionMetadata["connection"] = "remote"
    }
    if let reason = config.reason {
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
    let readyRunIndex: UInt32
    let sessionID: String
    let autoImportModules: [String]
    let interfaceSearchPaths: [String]
    let sdkPath: String
    let targetTriple: String
    let compilerArguments: [String]
    let linkerArguments: [String]
    do {
      toolchain = try resolveToolchainPath(explicit: config.toolchainPath)

      // Resolve the companion to connect to (see `resolveCompanionAddress`): an
      // explicit `--companion host:port`, otherwise a discovered companion.
      let address = try await resolveCompanionAddress(config: config)

      group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      channel = try GRPCChannelPool.with(
        target: connectionTarget(for: address),
        transportSecurity: try channelTransportSecurity(
          for: address, tls: planCompanionClientTLS(plaintext: config.plaintext)),
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
              if case let .test(bundlePath) = context {
                $0.testBundlePath = bundlePath
              }
              if case let .app(bundleID, reuseSession) = context {
                $0.appBundleID = bundleID
                $0.reuseSession = reuseSession
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
      readyRunIndex = ready.nextRunIndex
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
      compilerArguments = try resolveCompilerArguments(platform: platform)
      linkerArguments = try resolveLinkerArguments(platform: platform, runtimeOSVersion: osVersion)
      FileHandle.standardError.write(Data("idb-repl: compiling injected code for \(targetTriple)\n".utf8))
    } catch {
      reporter.report(
        ReplRunTelemetry.subject(
          name: "start_session", start: sessionStart, failure: "\(error)", stage: .connect))
      throw error
    }
    reporter.report(ReplRunTelemetry.subject(name: "start_session", start: sessionStart, failure: nil))

    // The app was freshly launched iff the companion resumes numbering from zero (no
    // prior runs from a reattached REPL). Recorded for app sessions so `replay` can
    // reproduce the same launch mode.
    let freshLaunch = (readyRunIndex == 0)

    // Set up the session report if a path was given. Best-effort: failing to open
    // it disables reporting but never stops the REPL.
    var reportWriter: ReplReportWriter?
    if let reportPath = config.reportPath {
      let writer = ReplReportWriter(path: reportPath)
      if let resolvedPath = writer.open(
        meta: context.sessionMeta(freshLaunch: freshLaunch),
        target: "\(deviceType) \(osVersion)",
        reason: config.reason,
        sessionID: sessionID,
        startedAt: Date())
      {
        FileHandle.standardError.write(Data("idb-repl: writing session report to \(resolvedPath)\n".utf8))
        reportWriter = writer
      }
    }

    return ReplSession(
      config: config,
      reporter: reporter,
      startedAt: sessionStart,
      group: group,
      channel: channel,
      call: call,
      client: client,
      responses: responses,
      deviceType: deviceType,
      osVersion: osVersion,
      sessionID: sessionID,
      freshLaunch: freshLaunch,
      nextRunIndex: Int(readyRunIndex),
      toolchain: toolchain,
      targetTriple: targetTriple,
      sdkPath: sdkPath,
      compilerArguments: compilerArguments,
      linkerArguments: linkerArguments,
      interfaceSearchPaths: interfaceSearchPaths,
      autoImportModules: autoImportModules,
      reportWriter: reportWriter)
  }

  /// Compiles `code` into a dylib, injects and executes it against the target, and
  /// returns the result. Advances `nextRunIndex`, transfers any captured artifacts, and
  /// records the run to the report. Records a compile failure to the report only when
  /// `--report-failures` was given; either way the error is re-thrown for the caller to
  /// surface. Reports run telemetry for both success and failure.
  func execute(code: String) async throws -> ExecutionResult {
    let index = nextRunIndex
    let start = Date()
    runsExecuted += 1
    // Advanced as the run progresses, so a failure row records the phase the
    // run was in when it failed.
    var stage = ReplRunStage.compile
    do {
      let parameters = ReplCompileParameters(
        targetTriple: targetTriple,
        sdkPath: sdkPath,
        toolchainPath: toolchain,
        compilerArguments: compilerArguments,
        interfaceSearchPaths: interfaceSearchPaths,
        autoImportModules: autoImportModules,
        linkerArguments: linkerArguments)
      let dylib: Data
      let symbol: String
      switch try ReplCompiler.compile(userCode: code, index: index, parameters: parameters, workingDirectory: sessionDirectory.path) {
      case let .success(dylibPath, compiledSymbol):
        dylib = try Data(contentsOf: URL(fileURLWithPath: dylibPath))
        symbol = compiledSymbol
      case let .failure(compilerOutput):
        throw ReplExecutionError.compileFailed(compilerOutput)
      }
      stage = .inject
      try await call.requestStream.send(
        .with {
          $0.control = .execute(
            .with {
              $0.dylib = dylib
              $0.symbol = symbol
            })
        })
      stage = .execute
      switch try await responses.next()?.event {
      case let .result(result):
        let artifactFilenames = await Self.transferArtifacts(result.artifacts, client: client, into: reportWriter)
        reportWriter?.recordRun(index: index, code: code, output: result.output, artifactFilenames: artifactFilenames, at: Date())
        let rawNext = Int(result.nextRunIndex)
        nextRunIndex = rawNext >= 0 ? rawNext : 0
        reporter.report(
          ReplRunTelemetry.subject(
            name: "run",
            start: start,
            ints: ReplRunTelemetry.codeMetrics(code),
            failure: nil))
        return ExecutionResult(output: result.output, nextIndex: rawNext, artifactFilenames: artifactFilenames)
      case let .stopped(stopped):
        throw ReplExecutionError.sessionStopped(stopped.desc)
      case .ready:
        throw ReplExecutionError.unexpectedReady
      case .none:
        throw ReplExecutionError.streamClosed
      }
    } catch {
      if config.reportFailures, case let ReplExecutionError.compileFailed(compilerOutput) = error {
        reportWriter?.recordCompileFailure(index: index, code: code, compilerOutput: compilerOutput, at: Date())
      }
      reporter.report(
        ReplRunTelemetry.subject(
          name: "run",
          start: start,
          ints: ReplRunTelemetry.codeMetrics(code),
          failure: "\(error)",
          stage: stage))
      throw error
    }
  }

  /// Closes the report and tears down the gRPC stream, channel, and event-loop group,
  /// then cleans up the session's scratch directory. Reports the `session_end`
  /// event carrying the session's duration and how many runs it executed —
  /// which makes sessions that never ran code visible.
  func finish() async {
    reporter.report(
      ReplRunTelemetry.subject(
        name: "session_end", start: startedAt, ints: ["runs": runsExecuted], failure: nil))
    reportWriter?.close()
    try? await call.requestStream.finish()
    try? await channel.close().get()
    try? await group.shutdownGracefully()
    sessionDirectory.cleanup()
  }

  // MARK: - Connection

  /// Resolves the companion address to connect to. `--companion host:port`
  /// connects directly to an explicit (typically remote) TCP companion, bypassing
  /// discovery, matching idb-forward. Otherwise a companion is discovered — by
  /// `--udid`, or the single running / only-available-simulator default — and
  /// started if needed, exiting after 5 minutes without gRPC activity so it does
  /// not outlive its use.
  ///
  /// Whether local discovery is available is decided by `CompanionDiscovery`
  /// (`planCompanionRoute`): it spawns and talks to a local `idb_companion`, which
  /// exists only on macOS, so on other platforms an explicit `--companion` is
  /// required.
  private static func resolveCompanionAddress(config: ReplSessionConfig) async throws -> CompanionAddress {
    switch planCompanionRoute(companion: config.companion) {
    case let .tcp(companion):
      guard let address = CompanionAddress.parse(tcp: companion) else {
        throw ValidationError(
          "--companion expects host:port, e.g. 127.0.0.1:10882 (got '\(companion)')")
      }
      return address
    case .discoverLocal:
      let idleShutdownTime = 5 * 60
      if let udid = config.udid {
        return try await companionManager(config: config)
          .companionInfo(forUDID: udid, idleShutdownTime: idleShutdownTime).address
      }
      return try await companionManager(config: config)
        .defaultCompanion(idleShutdownTime: idleShutdownTime).address
    case .localUnavailable:
      throw ValidationError(
        "idb-repl can only connect to a companion over TCP on this platform; please pass --companion <host:port>")
    }
  }

  private static func companionManager(config: ReplSessionConfig) -> CompanionManager {
    if let idbCompanionBinary = config.idbCompanionBinary {
      return CompanionManager(companionPath: idbCompanionBinary)
    }
    return CompanionManager()
  }

  /// Maps a discovered companion's address to a connection target.
  private static func connectionTarget(for address: CompanionAddress) -> ConnectionTarget {
    switch address {
    case let .domainSocket(path):
      return .unixDomainSocket(path)
    case let .tcp(host, port):
      return .hostAndPort(host, port)
    }
  }

  // MARK: - Artifacts

  /// Retrieves each artifact captured during a run and returns the filenames stored
  /// beside the session report (empty when no report is being written). Artifacts are
  /// stored next to the report — in its `artifactsDirectory()` — so the report can
  /// link them and they persist; without a report they land in the ephemeral session
  /// directory instead. When the companion shares our filesystem the file is moved
  /// directly; otherwise it is pulled over gRPC (the AUXILLARY container) and removed
  /// from the companion. Best-effort: failing to retrieve one artifact is logged and
  /// does not stop the session.
  private static func transferArtifacts(_ artifacts: [Idb_ReplResponse.Result.Artifact], client: Idb_CompanionServiceAsyncClient, into reportWriter: ReplReportWriter?) async -> [String] {
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
  private static func moveArtifact(hostPath: String, into directory: String) throws -> String {
    let destination = (directory as NSString).appendingPathComponent((hostPath as NSString).lastPathComponent)
    try? FileManager.default.removeItem(atPath: destination)
    try FileManager.default.moveItem(atPath: hostPath, toPath: destination)
    return destination
  }

  /// Pulls an artifact from the companion's AUXILLARY container (streamed back as a
  /// gzipped tar), extracts it into `directory`, and removes the companion copy.
  private static func pullArtifact(containerPath: String, client: Idb_CompanionServiceAsyncClient, into directory: String) async throws -> String {
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
    try extractArchive(at: archivePath, into: directory)

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
