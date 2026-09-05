/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
@preconcurrency import XCTestBootstrap

public enum FBSimulatorReplError: Error {
  case bundledResourceMissing(item: String)
  case socketDirectoryCreationFailed(path: String)
}

extension FBSimulatorReplError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .bundledResourceMissing(item):
      return "\(item) not found in the companion Resources directory"
    case let .socketDirectoryCreationFailed(path):
      return "Could not create a private REPL socket directory at \(path)"
    }
  }
}

public final class FBSimulatorReplCommands {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> FBSimulatorReplCommands {
    return FBSimulatorReplCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Async

  fileprivate func startReplTest(bundlePath: String) async throws -> ReplSession {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let logger = simulator.logger

    // The driver auto-imports the IDBAPI `.swiftinterface` so injected code can call `IDB`; the API
    // itself is linked into libRepl.
    guard let replDylibPath = BundledResources.path(forItem: "libRepl-iOS.dylib") else {
      throw FBSimulatorReplError.bundledResourceMissing(item: "libRepl-iOS.dylib")
    }
    let idbInterfacePath = BundledResources.path(forItem: "IDBAPI.swiftinterface")
    let extraInterfacePaths = idbInterfacePath.map { [$0] } ?? []

    // The shim binds this socket; the gRPC handler connects to it.
    let socketPath = "/tmp/idb_repl_\(UUID().uuidString).sock"

    let bundle = try FBBundleDescriptor.bundle(fromPath: bundlePath)
    let architectures = Set((bundle.binary?.architectures ?? []).map(\.rawValue))

    let configuration = FBLogicTestConfiguration(
      environment: [
        "IDB_REPL_SOCKET_PATH": socketPath,
        "IDB_REPL_GEN_INTERFACE_DIR": "/tmp/idb_repl_interfaces",
        "IDB_REPL_PROBE_IMAGE": "ReplTest",
      ],
      workingDirectory: simulator.auxillaryDirectory,
      testBundlePath: bundlePath,
      waitForDebugger: false,
      timeout: 3_600,
      testFilter: "TestRepl/start",
      mirroring: .fileLogs,
      coverageConfiguration: nil,
      binaryPath: bundle.binary?.path,
      logDirectoryPath: nil,
      architectures: architectures,
      injectLibraries: [replDylibPath]
    )

    let runner = FBLogicTestRunStrategy(
      target: simulator as any FBiOSTarget & ProcessSpawnCommands & XCTestExtendedCommands,
      configuration: configuration,
      reporter: ReplNullReporter(),
      logger: logger)
    return ReplSession(socketPath: socketPath, run: runner.execute(), extraInterfacePaths: extraInterfacePaths)
  }

  fileprivate func startReplSimulator() async throws -> ReplSession {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }

    guard let bridgePath = BundledResources.path(forItem: "SimulatorFrameworkBridge") else {
      throw FBSimulatorReplError.bundledResourceMissing(item: "SimulatorFrameworkBridge binary")
    }
    guard let libReplPath = BundledResources.path(forItem: "libRepl-iOS.dylib") else {
      throw FBSimulatorReplError.bundledResourceMissing(item: "libRepl-iOS.dylib")
    }
    let idbInterfacePath = BundledResources.path(forItem: "IDBAPI.swiftinterface")

    // `repl start` blocks until the socket is closed, which is what keeps the session alive.
    let socketPath = "/tmp/idb_repl_\(UUID().uuidString).sock"

    let io: FBProcessIO<AnyObject, AnyObject, AnyObject> = .outputToDevNull()
    let configuration = FBProcessSpawnConfiguration(
      launchPath: bridgePath,
      arguments: ["repl", "start", socketPath, libReplPath],
      environment: [:],
      io: io,
      mode: .posixSpawn
    )

    // Launch without waiting; `statLoc` completes when the bridge exits (once
    // the socket is closed), matching the `ReplSession.run` contract.
    let process = try await simulator.launchProcess(configuration)
    let run = unsafeBitCast(process.statLoc, to: FBFuture<NSNull>.self)
    return ReplSession(socketPath: socketPath, run: run, extraInterfacePaths: [idbInterfacePath].compactMap { $0 })
  }

  fileprivate func replAppEnvironment(bundleID: String) async throws -> [String: String] {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    guard let replDylibPath = BundledResources.path(forItem: "libRepl-iOS.dylib") else {
      throw FBSimulatorReplError.bundledResourceMissing(item: "libRepl-iOS.dylib")
    }
    return [
      "DYLD_INSERT_LIBRARIES": replDylibPath,
      "IDB_REPL_APP_AUTOSTART": "1",
      "IDB_REPL_SOCKET_PATH": replSocketPath(udid: simulator.udid, bundleID: bundleID),
    ]
  }

  fileprivate func startReplApp(bundleID: String, reuseSession: Bool) async throws -> ReplSession {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let logger = simulator.logger

    // Read host-side by the companion, so the app sandbox need not contain it.
    let idbInterfacePath = BundledResources.path(forItem: "IDBAPI.swiftinterface")
    let extraInterfacePaths = idbInterfacePath.map { [$0] } ?? []

    // Deterministic so a later `idb-repl app` can reattach to a still-running REPL.
    guard ensureReplSocketDirectory(replSocketDirectory()) else {
      throw FBSimulatorReplError.socketDirectoryCreationFailed(path: replSocketDirectory())
    }
    let socketPath = replSocketPath(udid: simulator.udid, bundleID: bundleID)

    if reuseSession, await replListenerIsAlive(at: socketPath) {
      logger.info().log("Reattaching to the running REPL for \(bundleID) at \(socketPath)")
      let run: FBFuture<NSNull> = FBFuture(result: NSNull())
      return ReplSession(socketPath: socketPath, run: run, extraInterfacePaths: extraInterfacePaths)
    }

    // `.relaunchIfRunning` so an app already running without the dylib picks it up.
    let environment = try await replAppEnvironment(bundleID: bundleID)
    let io: FBProcessIO<AnyObject, AnyObject, AnyObject> = .outputToDevNull()
    let configuration = FBApplicationLaunchConfiguration(
      bundleID: bundleID,
      bundleName: nil,
      arguments: [],
      environment: environment,
      waitForDebugger: false,
      io: io,
      launchMode: .relaunchIfRunning
    )
    _ = try await simulator.launchApplication(configuration)

    // The app outlives the REPL session -- it keeps running and resets for the
    // next client on disconnect -- so `run` is already resolved: teardown must not
    // wait for the app to exit.
    let run: FBFuture<NSNull> = FBFuture(result: NSNull())
    return ReplSession(socketPath: socketPath, run: run, extraInterfacePaths: extraInterfacePaths)
  }
}

// MARK: - FBSimulator+ReplCommands

extension FBSimulator: ReplCommands {

  public func startReplTest(bundlePath: String) async throws -> ReplSession {
    try await repl.startReplTest(bundlePath: bundlePath)
  }

  public func startReplSimulator() async throws -> ReplSession {
    try await repl.startReplSimulator()
  }

  public func startReplApp(bundleID: String, reuseSession: Bool) async throws -> ReplSession {
    try await repl.startReplApp(bundleID: bundleID, reuseSession: reuseSession)
  }

  public func replAppLaunchEnvironment(bundleID: String) async throws -> [String: String] {
    try await repl.replAppEnvironment(bundleID: bundleID)
  }
}

// MARK: - Reporter

/// A no-op logic-test reporter. REPL mode runs the shim's single test purely to
/// host the control socket, so the normal test-reporting events are discarded.
final class ReplNullReporter: FBLogicXCTestReporter {
  func processWaitingForDebugger(withProcessIdentifier pid: pid_t) {}
  func didBeginExecutingTestPlan() {}
  func didFinishExecutingTestPlan() {}
  func testHadOutput(_ output: String) {}
  func handleEventJSONData(_ data: Data) {}
  func didCrashDuringTest(_ error: Error) {}
}

// MARK: - App-context REPL socket helpers

/// The per-user directory that holds app-context REPL control sockets. Placed
/// under /tmp -- a namespace shared between the host companion and the simulator
/// app (which runs as the same user) -- but scoped to the owning user by a 0700
/// directory.
func replSocketDirectory() -> String {
  return "/tmp/idb_repl_\(getuid())"
}

/// Verifies with `lstat` rather than trusting creation: the directory may pre-exist with the wrong
/// owner or mode.
@discardableResult
func ensureReplSocketDirectory(_ dir: String) -> Bool {
  let fm = FileManager.default
  if !fm.fileExists(atPath: dir) {
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  }
  var st = stat()
  guard lstat(dir, &st) == 0 else { return false }
  return (st.st_mode & UInt16(S_IFMT)) == UInt16(S_IFDIR)
    && st.st_uid == getuid()
    && (st.st_mode & 0o777) == 0o700
}

/// The deterministic control socket path for an app-context REPL, derived from
/// the simulator udid and app bundle id, inside the per-user socket directory.
/// Reattach relies on this being stable across `idb-repl` invocations and
/// companion restarts. Hashed to a fixed length: `sockaddr_un.sun_path` is only
/// 104 bytes, so the raw udid + bundle id would not reliably fit.
func replSocketPath(udid: String, bundleID: String) -> String {
  return "\(replSocketDirectory())/\(stableHashHex("\(udid)\u{0}\(bundleID)")).sock"
}

/// A stable, process-independent 64-bit FNV-1a hash of `string` as 16 hex
/// digits. Swift's `Hasher` is seeded per process, so it cannot back a path
/// that must match across processes.
func stableHashHex(_ string: String) -> String {
  var hash: UInt64 = 0xcbf2_9ce4_8422_2325
  for byte in string.utf8 {
    hash ^= UInt64(byte)
    hash = hash &* 0x0000_0100_0000_01b3
  }
  let hex = String(hash, radix: 16)
  return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
}

/// Whether a REPL control socket is already listening at `path`. A single, fast
/// connect attempt: connect() to an absent or dead socket fails at once
/// (ENOENT/ECONNREFUSED), so a closed app is detected without waiting.
func replListenerIsAlive(at path: String) async -> Bool {
  let queue = DispatchQueue(label: "com.facebook.idb.repl.probe")
  return await withCheckedContinuation { continuation in
    queue.async {
      let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
      guard fd >= 0 else {
        continuation.resume(returning: false)
        return
      }
      defer { Darwin.close(fd) }
      var addr = sockaddr_un()
      addr.sun_family = sa_family_t(AF_UNIX)
      let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
      guard path.utf8.count < maxLength else {
        continuation.resume(returning: false)
        return
      }
      _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        path.withCString { src in memcpy(ptr, src, path.utf8.count + 1) }
      }
      let size = socklen_t(MemoryLayout<sockaddr_un>.size)
      let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
          Darwin.connect(fd, sockPtr, size)
        }
      }
      continuation.resume(returning: result == 0)
    }
  }
}
