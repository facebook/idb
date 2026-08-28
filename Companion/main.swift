/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import CompanionUtilities
import FBControlCore
import FBDeviceControl
import FBSimulatorControl
import Foundation
import XCTestBootstrap

// @oss-disable
  // @oss-disable
// @oss-disable

/// The ways companion startup and one-shot modes can fail, as data rather than assembled strings.
enum IDBCompanionError: Error {
  case invalidOnlyArgument(argument: String)
  case noDevicesMatchingECID(ecid: String)
  case simulatorLifecycleUnsupported(targetDescription: String)
  case lifecycleUnsupported(targetDescription: String)
  case shutdownUnsupported(targetDescription: String)
  case rebootUnsupported(targetDescription: String)
  case eraseUnsupported(targetDescription: String)
  case simulatorNotFound(udid: String)
  case invalidForwardArgument(argument: String)
  case socketForwardingUnsupported(targetDescription: String)
  case noModeOfOperation(usage: String)
}

extension IDBCompanionError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case let .invalidOnlyArgument(argument):
      return "\(argument) is not a valid argument for '--only'"
    case let .noDevicesMatchingECID(ecid):
      return "No devices [] matching \(ecid)"
    case let .simulatorLifecycleUnsupported(targetDescription):
      return "\(targetDescription) does not support Simulator Lifecycle commands"
    case let .lifecycleUnsupported(targetDescription):
      return "\(targetDescription) does not support LifecycleCommands"
    case let .shutdownUnsupported(targetDescription):
      return "Cannot shutdown \(targetDescription), does not support shutting down"
    case let .rebootUnsupported(targetDescription):
      return "Cannot shutdown \(targetDescription), does not support rebooting"
    case let .eraseUnsupported(targetDescription):
      return "Cannot erase \(targetDescription), does not support erasing"
    case let .simulatorNotFound(udid):
      return "Could not find a simulator with udid \(udid)"
    case let .invalidForwardArgument(argument):
      return "\(argument) should be of the form UDID:PORT"
    case let .socketForwardingUnsupported(targetDescription):
      return "\(targetDescription) does not conform to SocketForwardingCommands"
    case let .noModeOfOperation(usage):
      return "You must specify at least one 'Mode of operation'\n\n\(usage)"
    }
  }
}

private let kUsageHelpMessage = """
  Usage:
    Modes of operation, only one of these may be specified:
      --udid UDID|mac|only       Launches a companion server for the specified UDID, 'mac' for a mac companion, or 'only' to run a companion for the only simulator/device available.
      --boot UDID                Boots the simulator with the specified UDID.
      --reboot UDID              Reboots the target with the specified UDID.
      --shutdown UDID            Shuts down the target with the specified UDID.
      --erase UDID               Erases the target with the specified UDID.
      --clean UDID               Performs a soft reset to the specified UDID.
      --delete UDID|all          Deletes the simulator with the specified UDID, or 'all' to delete all simulators in the set.
      --create VALUE             Creates a simulator using the VALUE argument like "iPhone X,iOS 12.4"
      --clone UDID               Clones a simulator by a given UDID
      --clone-destination-set    A path to the destination device set in a clone operation, --device-set-path specifies the source simulator.
      --recover ecid:ECID        Causes the targeted device ECID to enter recovery mode
      --unrecover ecid:ECID      Causes the targeted device ECID to exit recovery mode
      --activate ecid:ECID       Causes the device to activate
      --notify PATH|stdout       Launches a companion notifier which will stream availability updates to the specified path, or stdout.
      --forward UDID:PORT        Forwards the remote socket for the specified UDID to the specified remote PORT. Input and output is relayed via stdin/stdout
      --list 1                   Lists all available devices and simulators in the current context. If Xcode is not correctly installed, only devices will be listed.
      --version                  Writes companion version information to stdout.
      --help                     Show this help message and exit.

    Options:
      --grpc-port PORT           Port to start the grpc companion server on (default: 10882).
      --tls-cert-path PATH       If specified exposed GRPC server will be listening on a TLS enabled socket.
      --grpc-domain-sock PATH    Unix Domain Socket path to start the companion server on, will superceed TCP binding via --grpc-port.
      --debug-port PORT          Port to connect debugger on (default: 10881).
      --log-file-path PATH       Path to write a log file to e.g ./output.log (default: logs to stdErr).
      --log-level info|debug     The log level to use, 'debug' for a higher level of debugging 'info' for a lower level of logging (default 'debug').
      --device-set-path PATH     Path to a custom Simulator device set.
      --only FILTER_OPTION       If provided, will limit interaction to a subset of all available targets
      --headless VALUE           If VALUE is a true value, the Simulator boot's lifecycle will be tied to the lifecycle of this invocation.
      --verify-booted VALUE      If VALUE is a true value, will verify that the Simulator is in a known-booted state before --boot completes. Default is true.
      --terminate-offline VALUE  Terminate if the target goes offline, otherwise the companion will stay alive.
      --idle-shutdown-time SECS  Exit after SECS seconds with no active or newly received gRPC requests (default: stays alive).

   Filter Options:
      simulator                  Limit interactions to Simulators only.
      device                     Limit interactions to Devices only.
      ecid:ECID                  Limit interactions to a specific Device ECID
  """

private let kXcodeHelpMessage = """

  ====================================================================
  Xcode is required. Please make sure Xcode is installed and then run:
  sudo xcode-select --switch $(ls -td /Applications/Xcode* | head -1)
  ====================================================================

  """

/// The outcome of the companion's main work, used to race the selected command
/// against the signal handler via `Task.select`.
private enum CompanionOutcome: Sendable {
  case finished
  case signalled(Int32)
}

private func writeJSONToStdOut(_ json: Any) {
  guard let jsonOutput = try? JSONSerialization.data(withJSONObject: json) else { return }
  var readyOutput = Data(jsonOutput)
  if let newline = "\n".data(using: .utf8) {
    readyOutput.append(newline)
  }
  writeToStandardOutput(readyOutput)
  fflush(stdout)
}

private func writeTargetToStdOut(_ target: FBiOSTargetInfo) {
  writeJSONToStdOut(FBiOSTargetDescription(target: target).asJSON)
}

private func simulatorSetWithPath(_ deviceSetPath: String?, logger: FBControlCoreLogger) throws -> FBSimulatorSet {
  // Give a more meaningful message if we can't load the frameworks.
  try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(logger)
  let configuration = FBSimulatorControlConfiguration(deviceSetPath: deviceSetPath, logger: logger)
  return try FBSimulatorControl.withConfiguration(configuration).set
}

private func simulatorSet(_ userDefaults: UserDefaults, logger: FBControlCoreLogger) throws -> FBSimulatorSet {
  let deviceSetPath = userDefaults.string(forKey: "-device-set-path")
  return try simulatorSetWithPath(deviceSetPath, logger: logger)
}

/// How long a device-targeted invocation waits for MobileDevice to report a
/// device before giving up and letting the caller report an empty set. Sized
/// well above observed discovery times, since overshooting only costs a host
/// with no device attached, while undershooting fails the whole session.
private let deviceDiscoveryTimeout: TimeInterval = 5
private let deviceDiscoveryPollInterval: TimeInterval = 0.1
/// Unconditional nap retained for callers that tolerate an empty device set.
private let restorableDevicePopulationNap: UInt64 = 200_000_000

private func deviceSet(_ logger: FBControlCoreLogger, ecidFilter: String?, waitForDevices: Bool = false) async throws -> FBDeviceSet {
  // `FBDeviceSet` hardcodes `DispatchQueue.main` for its device managers and
  // registers MobileDevice notifications that expect the main run loop, so it
  // must be created on the main thread.
  let set: FBDeviceSet = try await withCheckedThrowingContinuation { continuation in
    DispatchQueue.main.async {
      do {
        // Give a more meaningful message if we can't load the frameworks.
        try FBDeviceControlFrameworkLoader().loadPrivateFrameworks(logger)
        continuation.resume(returning: try FBDeviceSet(logger: logger, delegate: nil, ecidFilter: ecidFilter))
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
  guard waitForDevices else {
    // This is needed to give the Restorable Devices time to populate.
    try await Task.sleep(nanoseconds: restorableDevicePopulationNap)
    return set
  }
  try await awaitDevicePopulation(of: set, logger: logger)
  return set
}

/// Waits for at least one device to land in `set`.
///
/// Devices arrive asynchronously, over MobileDevice notifications delivered to
/// the main run loop, so a freshly constructed set is briefly empty. A caller
/// resolving `--udid only` against it therefore sees no targets at all unless it
/// waits, and a fixed nap loses that race whenever discovery runs slower than
/// the nap -- leaving the companion to exit before it ever binds its socket.
///
/// `allTargetInfos` is polled rather than `allDevices` because that is what
/// target resolution reads, though on `FBDeviceSet` the two are the same list.
///
/// Timing out is not an error here: a host with no device attached should still
/// get the caller's usual "no targets" message rather than one about discovery.
private func awaitDevicePopulation(of set: FBDeviceSet, logger: FBControlCoreLogger) async throws {
  do {
    try await Task.timeout(nanoseconds: UInt64(deviceDiscoveryTimeout * Double(NSEC_PER_SEC))) {
      // The set is mutated on the main queue, so the condition is polled there.
      try await pollUntilTrue(on: .main, interval: deviceDiscoveryPollInterval) {
        !set.allTargetInfos.isEmpty
      }
    }
  } catch {
    // A timeout is tolerated, but cancellation must still propagate.
    try Task.checkCancellation()
    logger.log("No devices appeared within \(deviceDiscoveryTimeout)s of creating the device set")
  }
}

private func defaultTargetSets(_ userDefaults: UserDefaults, xcodeAvailable: Bool, waitForDevices: Bool = false, logger: FBControlCoreLogger) async throws -> [FBiOSTargetSet] {
  let only = userDefaults.string(forKey: "-only")
  if let only {
    if only.lowercased().contains("simulator") {
      logger.log("'--only' set for Simulators")
      return [try simulatorSet(userDefaults, logger: logger)]
    }
    if only.lowercased().contains("device") {
      logger.log("'--only' set for Devices")
      return [try await deviceSet(logger, ecidFilter: nil, waitForDevices: true)]
    }
    if only.lowercased().hasPrefix("ecid:") {
      let ecid = only.lowercased().replacingOccurrences(of: "ecid:", with: "")
      logger.log("ECID filter of \(ecid)")
      return [try await deviceSet(logger, ecidFilter: ecid, waitForDevices: true)]
    }
    throw IDBCompanionError.invalidOnlyArgument(argument: only)
  }
  if !xcodeAvailable {
    logger.log("Xcode is not available, only Devices will be provided")
    return [try await deviceSet(logger, ecidFilter: nil, waitForDevices: true)]
  }
  logger.log("Providing targets across Simulator and Device sets.")
  return [
    try simulatorSet(userDefaults, logger: logger),
    try await deviceSet(logger, ecidFilter: nil, waitForDevices: waitForDevices),
  ]
}

private func targetForUDID(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, warmUp: Bool, logger: FBControlCoreLogger) async throws -> FBiOSTarget {
  let targetSets = try await defaultTargetSets(userDefaults, xcodeAvailable: xcodeAvailable, logger: logger)
  return try FBiOSTargetProvider.target(withUDID: udid, targetSets: targetSets, warmUp: warmUp, logger: logger)
}

private func deviceForECID(_ ecid: String, logger: FBControlCoreLogger) async throws -> FBDevice {
  let set = try await deviceSet(logger, ecidFilter: ecid.replacingOccurrences(of: "ecid:", with: ""), waitForDevices: true)
  let devices = set.allDevices
  if devices.isEmpty {
    throw IDBCompanionError.noDevicesMatchingECID(ecid: ecid)
  }
  return devices[0]
}

private func resolveSimulator(_ udid: String, userDefaults: UserDefaults, logger: FBControlCoreLogger) async throws -> FBSimulator {
  let set = try simulatorSet(userDefaults, logger: logger)
  let target = try FBiOSTargetProvider.target(withUDID: udid, targetSets: [set], warmUp: false, logger: logger)
  guard target is SimulatorLifecycleCommands, let simulator = target as? FBSimulator else {
    throw IDBCompanionError.simulatorLifecycleUnsupported(targetDescription: String(describing: target))
  }
  return simulator
}

private func awaitTargetOffline(_ target: FBiOSTarget, logger: FBControlCoreLogger) async throws {
  guard let asyncTarget = target as? any LifecycleCommands else {
    throw IDBCompanionError.lifecycleUnsupported(targetDescription: String(describing: target))
  }
  try await asyncTarget.resolveLeavesState(.booted)
  target.logger.log("Target is no longer booted, companion going offline")
}

private func runBoot(_ udid: String, userDefaults: UserDefaults, logger: FBControlCoreLogger) async throws {
  let headless = userDefaults.bool(forKey: "-headless")
  let verifyBooted = userDefaults.object(forKey: "-verify-booted") == nil ? true : userDefaults.bool(forKey: "-verify-booted")
  let simulator = try await resolveSimulator(udid, userDefaults: userDefaults, logger: logger)

  // Boot the simulator with the options provided.
  var options = FBSimulatorBootConfiguration.default.options
  if headless {
    logger.log("Booting \(udid) headlessly")
    options.insert(.tieToProcessLifecycle)
  } else {
    logger.log("Booting \(udid) normally")
    options.remove(.tieToProcessLifecycle)
  }
  if verifyBooted {
    logger.log("Booting \(udid) with verification")
    options.insert(.verifyUsable)
  } else {
    logger.log("Booting \(udid) without verification")
    options.remove(.verifyUsable)
  }
  let config = FBSimulatorBootConfiguration(options: options, environment: [:])
  try await simulator.boot(config)

  // Write the boot success to stdout
  writeTargetToStdOut(simulator)

  // In a headless boot:
  // - We need to keep this process running until it's otherwise shutdown. When the sim is shutdown this process will die.
  // - If this process is manually killed then the simulator will die
  // For a regular boot the sim will outlive this process.
  if !headless {
    return
  }

  // Whilst we can rely on this process being killed shutting the simulator, this is asynchronous.
  // This means that we should attempt to handle cancellation gracefully.
  // In this case we should attempt to shutdown in response to cancellation, and wait for it.
  do {
    try await awaitTargetOffline(simulator, logger: logger)
  } catch {
    // Includes CancellationError on signal. A fresh, unstructured Task does not
    // inherit the parent's cancelled state, so the shutdown runs to completion;
    // we await it before rethrowing so the sim is down before we exit.
    let shutdown = Task { try await simulator.shutdown() }
    _ = try? await shutdown.value
    throw error
  }
}

private func runShutdown(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger) async throws {
  let target = try await targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: false, logger: logger)
  guard let powerTarget = target as? any PowerCommands else {
    throw IDBCompanionError.shutdownUnsupported(targetDescription: String(describing: target))
  }
  try await powerTarget.shutdown()
}

private func runReboot(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger) async throws {
  let target = try await targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: false, logger: logger)
  guard let powerTarget = target as? any PowerCommands else {
    throw IDBCompanionError.rebootUnsupported(targetDescription: String(describing: target))
  }
  try await powerTarget.reboot()
}

private func runErase(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger) async throws {
  let target = try await targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: false, logger: logger)
  guard let eraseTarget = target as? any EraseCommands else {
    throw IDBCompanionError.eraseUnsupported(targetDescription: String(describing: target))
  }
  try await eraseTarget.erase()
}

private func runDelete(_ udidOrAll: String, userDefaults: UserDefaults, logger: FBControlCoreLogger) async throws {
  let set = try simulatorSet(userDefaults, logger: logger)
  if udidOrAll.lowercased() == "all" {
    try await bridgeFBFutureVoid(set.deleteAll())
    return
  }
  guard let simulator = set.simulator(withUDID: udidOrAll) else {
    throw IDBCompanionError.simulatorNotFound(udid: udidOrAll)
  }
  try await bridgeFBFutureVoid(set.delete(simulator))
}

private func runList(_ userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger) async throws {
  let targetSets = try await defaultTargetSets(userDefaults, xcodeAvailable: xcodeAvailable, waitForDevices: true, logger: logger)
  var reportedCount: UInt = 0
  for targetSet in targetSets {
    for targetInfo in targetSet.allTargetInfos {
      writeTargetToStdOut(targetInfo)
      reportedCount += 1
    }
  }
  logger.log("Reported \(reportedCount) targets to stdout")
}

private func runCreate(_ create: String, userDefaults: UserDefaults, logger: FBControlCoreLogger) async throws {
  let parameters = create.components(separatedBy: ",")
  var config = try FBSimulatorConfiguration.defaultConfiguration()
  if parameters.count > 0 {
    config = config.withDeviceModel(FBDeviceModel(rawValue: parameters[0]))
  }
  if parameters.count > 1 {
    config = config.withOSNamed(FBOSVersionName(rawValue: parameters[1]))
  }
  let set = try simulatorSet(userDefaults, logger: logger)
  let simulator = try await set.createSimulatorAsync(with: config)
  writeTargetToStdOut(simulator)
}

private func runClone(_ udid: String, userDefaults: UserDefaults, logger: FBControlCoreLogger) async throws {
  let destinationSet = userDefaults.string(forKey: "-clone-destination-set")
  let base = try await resolveSimulator(udid, userDefaults: userDefaults, logger: logger)
  let destination = try simulatorSetWithPath(destinationSet, logger: logger)
  guard let baseSet = base.set else {
    throw FBSimulatorSetError.simulatorHasNoSet(udid: base.udid)
  }
  let cloned = try await bridgeFBFuture(baseSet.cloneSimulator(base, toDeviceSet: destination))
  writeTargetToStdOut(cloned)
}

private func runEnterRecovery(_ ecid: String, logger: FBControlCoreLogger) async throws {
  let device = try await deviceForECID(ecid, logger: logger)
  try await device.enterRecovery()
}

private func runExitRecovery(_ ecid: String, logger: FBControlCoreLogger) async throws {
  let device = try await deviceForECID(ecid, logger: logger)
  try await device.exitRecovery()
}

private func runActivate(_ ecid: String, logger: FBControlCoreLogger) async throws {
  let device = try await deviceForECID(ecid, logger: logger)
  try await device.activate()
}

private func runClean(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBIDBLogger) async throws {
  let target = try await targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: true, logger: logger)
  let storageManager = try FBIDBStorageManager.manager(forTarget: target, logger: logger)
  let commandExecutor = try FBIDBCommandExecutor.commandExecutor(
    forTarget: target,
    storageManager: storageManager,
    temporaryDirectory: FBTemporaryDirectory(logger: logger),
    debugserverPort: in_port_t(IDBPortsConfiguration(arguments: userDefaults).debugserverPort),
    logger: logger
  )
  try await commandExecutor.clean()
}

private func runCompanionServer(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBIDBLogger, reporter: FBEventReporter) async throws {
  let terminateOffline = userDefaults.bool(forKey: "-terminate-offline")
  let idleShutdownTime = userDefaults.string(forKey: "-idle-shutdown-time").flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }

  let target = try await targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: true, logger: logger)

  reporter.addMetadata([
    "udid": udid,
    "target_type": FBiOSTargetTypeStringFromTargetType(target.targetType).lowercased(),
  ])
  reporter.report(FBEventReporterSubject(forEvent: "launched"))

  let temporaryDirectory = FBTemporaryDirectory(logger: logger)
  let storageManager = try FBIDBStorageManager.manager(forTarget: target, logger: logger)

  // Start up the companion
  let ports = IDBPortsConfiguration(arguments: userDefaults)

  // The gRPC domain socket this companion serves on, if any. Removing it
  // the instant shutdown begins stops clients from discovering a
  // companion that is already shutting down.
  let registeredSocketPath: String?
  if case let .unixDomainSocket(path) = ports.swiftServerTarget {
    registeredSocketPath = path
  } else {
    registeredSocketPath = nil
  }
  let removeRegisteredSocket: @Sendable () -> Void = {
    if let registeredSocketPath {
      Darwin.unlink(registeredSocketPath)
    }
  }

  // Command Executor
  let commandExecutor = try FBIDBCommandExecutor.commandExecutor(
    forTarget: target,
    storageManager: storageManager,
    temporaryDirectory: temporaryDirectory,
    debugserverPort: in_port_t(ports.debugserverPort),
    logger: logger
  )

  // Give the monitor the socket cleanup so an idle shutdown unlinks the
  // socket synchronously the instant it begins, ahead of the async teardown.
  let idleMonitor = idleShutdownTime.map {
    IdleMonitor(idleTime: $0, logger: logger, onShutdownStarted: removeRegisteredSocket)
  }

  let swiftServer = try GRPCSwiftServer(
    target: target,
    commandExecutor: commandExecutor,
    reporter: reporter,
    logger: logger,
    ports: ports,
    idleMonitor: idleMonitor,
    onShutdownStarted: removeRegisteredSocket
  )

  let serverDescription = try await swiftServer.start()
  writeJSONToStdOut(serverDescription)

  // Catch-all teardown for every exit path (normal completion, error, or
  // cancellation): mirrors the old `chain:` handler. An idle shutdown also
  // removes the socket synchronously the instant it fires.
  defer {
    temporaryDirectory.cleanOnExit()
    removeRegisteredSocket()
  }

  if let idleMonitor, let idleShutdownTime {
    logger.info().log("Companion will shut down after \(Int(idleShutdownTime))s of inactivity")
    idleMonitor.start()
  }
  if terminateOffline {
    logger.info().log("Companion will terminate when target goes offline")
  } else {
    logger.info().log("Companion will stay alive if target goes offline")
  }

  // Race the completion conditions; whichever resolves first ends the companion.
  // `Task.select` does not cancel the losers on the win path, so cancel them via
  // `defer`. If this command is cancelled (signal), `Task.select`'s own
  // `onCancel` cancels these children for us.
  var raceTasks: [Task<Void, Error>] = [Task { try await swiftServer.waitUntilClosed() }]
  if let idleMonitor {
    raceTasks.append(Task { try await idleMonitor.waitUntilExpired() })
  }
  if terminateOffline {
    nonisolated(unsafe) let target = target
    raceTasks.append(Task { try await awaitTargetOffline(target, logger: logger) })
  }
  defer { raceTasks.forEach { $0.cancel() } }
  _ = try await Task.select(raceTasks).value
}

private func runNotifier(_ notify: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger) async throws {
  let targetSets = try await defaultTargetSets(userDefaults, xcodeAvailable: xcodeAvailable, logger: logger)
  let notifier: FBiOSTargetStateChangeNotifier
  if notify == "stdout" {
    notifier = try FBiOSTargetStateChangeNotifier.notifierToStdOut(withTargetSets: targetSets, logger: logger)
  } else {
    notifier = try FBiOSTargetStateChangeNotifier.notifierToFilePath(notify, withTargetSets: targetSets, logger: logger)
  }
  logger.log("Starting Notifier \(notifier)")
  try notifier.startNotifier()
  logger.log("Started Notifier \(notifier)")
  do {
    try await notifier.waitUntilDone()
  } catch is CancellationError {
    logger.log("Stopping Notifier \(notifier)")
    throw CancellationError()
  }
}

private func runForward(_ forward: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger) async throws {
  let components = forward.components(separatedBy: ":")
  if components.count != 2 {
    throw IDBCompanionError.invalidForwardArgument(argument: forward)
  }
  let udid = components[0]
  let remotePort = Int32(components[1]) ?? 0

  let target = try await targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: false, logger: logger)
  guard let commands = target as? SocketForwardingCommands else {
    throw IDBCompanionError.socketForwardingUnsupported(targetDescription: String(describing: target))
  }
  try await commands.drainLocalFileInput(STDIN_FILENO, localFileOutput: STDOUT_FILENO, remotePort: remotePort)
}

/// Runs the single mode-of-operation selected by the command-line arguments,
/// returning once it has completed (the companion-server / boot / notify modes
/// run until they are shut down or cancelled).
private func runSelectedCommand(_ userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBIDBLogger) async throws {
  let boot = userDefaults.string(forKey: "-boot")
  let reboot = userDefaults.string(forKey: "-reboot")
  let clone = userDefaults.string(forKey: "-clone")
  let create = userDefaults.string(forKey: "-create")
  let deleteArg = userDefaults.string(forKey: "-delete")
  let erase = userDefaults.string(forKey: "-erase")
  let list = userDefaults.string(forKey: "-list")
  let notify = userDefaults.string(forKey: "-notify")
  let recover = userDefaults.string(forKey: "-recover")
  let shutdown = userDefaults.string(forKey: "-shutdown")
  let udid = userDefaults.string(forKey: "-udid")
  let unrecover = userDefaults.string(forKey: "-unrecover")
  let activate = userDefaults.string(forKey: "-activate")
  let clean = userDefaults.string(forKey: "-clean")
  let forward = userDefaults.string(forKey: "-forward")

  let reporter = IDBConfiguration.eventReporter
  if let udid {
    try await runCompanionServer(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter)
  } else if list != nil {
    logger.info().log("Listing")
    try await runList(userDefaults, xcodeAvailable: xcodeAvailable, logger: logger)
  } else if let notify {
    logger.info().log("Notifying \(notify)")
    try await runNotifier(notify, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger)
  } else if let boot {
    logger.log("Booting \(boot)")
    try await runBoot(boot, userDefaults: userDefaults, logger: logger)
  } else if let shutdown {
    logger.info().log("Shutting down \(shutdown)")
    try await runShutdown(shutdown, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger)
  } else if let reboot {
    logger.info().log("Rebooting \(reboot)")
    try await runReboot(reboot, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger)
  } else if let erase {
    logger.info().log("Erasing \(erase)")
    try await runErase(erase, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger)
  } else if let deleteArg {
    logger.info().log("Deleting \(deleteArg)")
    try await runDelete(deleteArg, userDefaults: userDefaults, logger: logger)
  } else if let create {
    logger.info().log("Creating \(create)")
    try await runCreate(create, userDefaults: userDefaults, logger: logger)
  } else if let clone {
    logger.info().log("Cloning \(clone)")
    try await runClone(clone, userDefaults: userDefaults, logger: logger)
  } else if let recover {
    logger.info().log("Putting \(recover) into recovery")
    try await runEnterRecovery(recover, logger: logger)
  } else if let unrecover {
    logger.info().log("Removing \(unrecover) from recovery")
    try await runExitRecovery(unrecover, logger: logger)
  } else if let activate {
    logger.info().log("Activating \(activate)")
    try await runActivate(activate, logger: logger)
  } else if let clean {
    logger.info().log("Cleaning \(clean)")
    try await runClean(clean, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger)
  } else if let forward {
    logger.info().log("Forwarding \(forward)")
    try await runForward(forward, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger)
  } else {
    throw IDBCompanionError.noModeOfOperation(usage: kUsageHelpMessage)
  }
}

/// Suspends until `signalCode` is delivered, returning the signal number. The
/// default disposition is ignored (replaced by the dispatch source) to match the
/// legacy behavior; cancelling the awaiting task tears the source down.
private func waitForSignal(_ signalCode: Int32, exitMessage: String, logger: FBControlCoreLogger) async throws -> Int32 {
  let promise = AsyncPromise<Int32>()
  let source = DispatchSource.makeSignalSource(signal: signalCode, queue: DispatchQueue.main)
  source.setEventHandler {
    logger.error().log(exitMessage)
    promise.resolve(signalCode)
  }
  source.resume()
  var action = sigaction()
  action.__sigaction_u.__sa_handler = SIG_IGN
  sigaction(signalCode, &action, nil)
  defer { source.cancel() }
  return try await promise.value
}

/// Suspends until any of `signals` is delivered, returning the first signal
/// number seen.
private func waitForAnySignal(_ signals: [(code: Int32, message: String)], logger: FBControlCoreLogger) async throws -> Int32 {
  let tasks = signals.map { signal in
    Task { try await waitForSignal(signal.code, exitMessage: signal.message, logger: logger) }
  }
  defer { tasks.forEach { $0.cancel() } }
  return try await Task.select(tasks).value
}

private func archName() -> String {
  #if arch(arm64)
  return "arm64"
  #elseif arch(x86_64)
  return "x86_64"
  #else
  return "not supported"
  #endif
}

private func logStartupInfo(_ logger: FBIDBLogger) {
  logger.info().log("IDB Companion Built at \(kBuildDate) \(kBuildTime)")
  logger.info().log("IDB Companion architecture \(archName())")
  logger.info().log("Invoked with args=\(FBCollectionInformation.oneLineDescription(from: ProcessInfo.processInfo.arguments))")
}

private func idbMain() async -> Int32 {
  let arguments = ProcessInfo.processInfo.arguments
  if arguments.contains("--help") {
    // A requested help message is not an error: write to stdout and exit 0,
    // appending the trailing newline the multiline constant lacks.
    FileHandle.standardOutput.write(Data((kUsageHelpMessage + "\n").utf8))
    return 0
  }
  if arguments.contains("--version") {
    writeJSONToStdOut(["build_time": kBuildTime, "build_date": kBuildDate])
    return 0
  }

  let userDefaults = UserDefaults.standard
  let logger = FBIDBLogger.logger(withUserDefaults: userDefaults)
  logStartupInfo(logger)

  guard FBXcodeConfiguration.developerDirectory != "" else {
    logger.error().log("Failed to resolve the Xcode developer directory. Ensure Xcode is installed and selected with xcode-select.")
    fputs(kXcodeHelpMessage, stderr)
    return 1
  }

  let command = Task<CompanionOutcome, Error> {
    try await runSelectedCommand(userDefaults, xcodeAvailable: true, logger: logger)
    return .finished
  }
  let signals = Task<CompanionOutcome, Error> {
    .signalled(
      try await waitForAnySignal(
        [(SIGINT, "Signalled: SIGINT"), (SIGTERM, "Signalled: SIGTERM")],
        logger: logger))
  }

  // Race the command against the signal handler. `Task.select` returns the first
  // task to finish but does NOT cancel the loser, so cancel it explicitly.
  let winner = await Task.select(command, signals)
  do {
    switch try await winner.value {
    case .finished:
      signals.cancel()
      return 0
    case let .signalled(signo):
      // Cancelling the command propagates into its in-flight `Task.select`
      // (server/notifier race) or graceful-shutdown handler (headless boot), so
      // its teardown runs; await it before exiting.
      command.cancel()
      _ = try? await command.value
      logger.log("Responding to termination of idb with signo \(signo)")
      return 0
    }
  } catch {
    command.cancel()
    signals.cancel()
    logger.error().log(error.localizedDescription)
    return 1
  }
}

let result = await idbMain()

exit(result)
