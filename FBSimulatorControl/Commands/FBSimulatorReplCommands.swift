/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
@preconcurrency import XCTestBootstrap

public final class FBSimulatorReplCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> FBSimulatorReplCommands {
    // swiftlint:disable:next force_cast
    return FBSimulatorReplCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Async

  fileprivate func startReplTest(bundlePath: String) async throws -> ReplSession {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    guard let logger = simulator.logger else {
      throw FBSimulatorError.describe("Simulator has no logger").build()
    }

    // Resolve the REPL shim, which is bundled alongside the other shims, as is the
    // IDBAPI module's .swiftinterface (reported to the driver, which auto-imports it
    // so injected code reaches the API through `IDB`; the API code itself is linked
    // into libRepl, which is injected).
    let shimDirectory = try await bridgeFBFuture(FBXCTestShimConfiguration.findShimDirectory(onQueue: simulator.workQueue, logger: logger))
    let replDylibPath = shimDirectory.appendingPathComponent("libRepl-iOS.dylib")
    guard FileManager.default.fileExists(atPath: replDylibPath) else {
      throw FBSimulatorError.describe("REPL shim not found at expected location \(replDylibPath)").build()
    }
    let idbInterfacePath = shimDirectory.appendingPathComponent("IDBAPI.swiftinterface")
    let extraInterfacePaths = FileManager.default.fileExists(atPath: idbInterfacePath) ? [idbInterfacePath] : []

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
      timeout: 3_600, // 1 hour
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

    // The SimulatorFrameworkBridge binary is bundled alongside the shims, as are
    // libRepl (which the bridge loads to serve the REPL) and the IDBAPI module's
    // .swiftinterface (reported to the driver, which auto-imports it so injected
    // code reaches the API through `IDB`).
    let bundle = Bundle(for: FBSimulatorReplCommands.self)
    guard let bridgePath = bundle.path(forResource: "SimulatorFrameworkBridge", ofType: nil) else {
      throw FBSimulatorError.describe("SimulatorFrameworkBridge binary not found in bundle resources").build()
    }
    guard let libReplPath = bundle.path(forResource: "libRepl-iOS", ofType: "dylib") else {
      throw FBSimulatorError.describe("libRepl-iOS.dylib not found in bundle resources").build()
    }
    let idbInterfacePath = bundle.path(forResource: "IDBAPI", ofType: "swiftinterface")

    // The bridge's `repl start` action takes the socket path and libRepl's path
    // and serves the control socket there. Serving blocks until the socket is
    // closed, which is what keeps the session alive.
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
    guard let logger = simulator.logger else {
      throw FBSimulatorError.describe("Simulator has no logger").build()
    }
    let shimDirectory = try await bridgeFBFuture(FBXCTestShimConfiguration.findShimDirectory(onQueue: simulator.workQueue, logger: logger))
    let replDylibPath = shimDirectory.appendingPathComponent("libRepl-iOS.dylib")
    guard FileManager.default.fileExists(atPath: replDylibPath) else {
      throw FBSimulatorError.describe("REPL shim not found at expected location \(replDylibPath)").build()
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
    guard let logger = simulator.logger else {
      throw FBSimulatorError.describe("Simulator has no logger").build()
    }

    // Report the IDB API's .swiftinterface (bundled beside libRepl) so the driver
    // auto-imports it and injected app code can call IDB.*, as the test and
    // simulator contexts do. The companion reads it host-side, so the app sandbox
    // need not contain it.
    let shimDirectory = try await bridgeFBFuture(FBXCTestShimConfiguration.findShimDirectory(onQueue: simulator.workQueue, logger: logger))
    let idbInterfacePath = shimDirectory.appendingPathComponent("IDBAPI.swiftinterface")
    let extraInterfacePaths = FileManager.default.fileExists(atPath: idbInterfacePath) ? [idbInterfacePath] : []

    // Derive the control socket path deterministically from the simulator + app
    // so a later `idb-repl app` can find and reattach to a still-running REPL
    // instead of relaunching. Hashed to a fixed length that fits sockaddr_un, and
    // placed in a per-user 0700 directory so only the owning user can reach it.
    guard ensureReplSocketDirectory(replSocketDirectory()) else {
      throw FBSimulatorError.describe("Could not create a private REPL socket directory at \(replSocketDirectory())").build()
    }
    let socketPath = replSocketPath(udid: simulator.udid, bundleID: bundleID)

    // Reattach: if a REPL is already listening at this path, reuse the live app
    // (and its in-memory state) rather than relaunching. Skipped when
    // `reuseSession` is false. The app outlives the session, so `run` is already
    // resolved and teardown neither waits for nor kills it.
    if reuseSession, await replListenerIsAlive(at: socketPath) {
      logger.info().log("Reattaching to the running REPL for \(bundleID) at \(socketPath)")
      let run: FBFuture<NSNull> = FBFuture(result: NSNull())
      return ReplSession(socketPath: socketPath, run: run, extraInterfacePaths: extraInterfacePaths)
    }

    // No live REPL (or `reuseSession` is false): launch -- relaunching if the app is already
    // running (e.g. running without the REPL injected) so the relaunched process picks
    // up the dylib.
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
    try await replCommands().startReplTest(bundlePath: bundlePath)
  }

  public func startReplSimulator() async throws -> ReplSession {
    try await replCommands().startReplSimulator()
  }

  public func startReplApp(bundleID: String, reuseSession: Bool) async throws -> ReplSession {
    try await replCommands().startReplApp(bundleID: bundleID, reuseSession: reuseSession)
  }

  public func replAppLaunchEnvironment(bundleID: String) async throws -> [String: String] {
    try await replCommands().replAppEnvironment(bundleID: bundleID)
  }
}

// MARK: - Reporter

/// A no-op logic-test reporter. REPL mode runs the shim's single test purely to
/// host the control socket, so the normal test-reporting events are discarded.
final class ReplNullReporter: NSObject, FBLogicXCTestReporter {
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

/// Ensures `dir` exists as a private (0700) directory we own, safely: it creates
/// it 0700 if missing, then verifies via lstat that it is a real directory,
/// owned by the current user, with exactly 0700 permissions.
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
