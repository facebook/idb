/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import FBDeviceControl
import FBSimulatorControl
import Foundation
import XCTestBootstrap

// @oss-disable
  // @oss-disable
// @oss-disable

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

   Filter Options:
      simulator                  Limit interactions to Simulators only.
      device                     Limit interactions to Devices only.
      ecid:ECID                  Limit interactions to a specific Device ECID
  """

// futureWithFutures: is NS_SWIFT_UNAVAILABLE, so call via ObjC runtime
private func allFutures(_ futures: [AnyObject]) -> FBFuture<NSArray> {
  let cls: AnyObject = FBFuture<NSArray>.self
  let result = cls.perform(NSSelectorFromString("futureWithFutures:"), with: futures)!
  return unsafeDowncast(result.takeUnretainedValue(), to: FBFuture<NSArray>.self)
}

private func writeJSONToStdOut(_ json: Any) {
  guard let jsonOutput = try? JSONSerialization.data(withJSONObject: json) else { return }
  var readyOutput = Data(jsonOutput)
  if let newline = "\n".data(using: .utf8) {
    readyOutput.append(newline)
  }
  readyOutput.withUnsafeBytes { bytes in
    _ = Darwin.write(STDOUT_FILENO, bytes.baseAddress!, bytes.count)
  }
  fflush(stdout)
}

private func writeTargetToStdOut(_ target: FBiOSTargetInfo) {
  if let description = FBiOSTargetDescription(target: target) {
    writeJSONToStdOut(description.asJSON)
  }
}

private func simulatorSetWithPath(_ deviceSetPath: String?, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<FBSimulatorSet> {
  // Give a more meaningful message if we can't load the frameworks.
  do {
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(logger)
  } catch {
    return FBFuture(error: error)
  }
  let configuration = FBSimulatorControlConfiguration(deviceSetPath: deviceSetPath, logger: logger, reporter: reporter)
  do {
    let control = try FBSimulatorControl.withConfiguration(configuration)
    return FBFuture(result: control.set)
  } catch {
    return FBFuture(error: error)
  }
}

private func simulatorSet(_ userDefaults: UserDefaults, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<FBSimulatorSet> {
  let deviceSetPath = userDefaults.string(forKey: "-device-set-path")
  return simulatorSetWithPath(deviceSetPath, logger: logger, reporter: reporter)
}

private func deviceSet(_ logger: FBControlCoreLogger, ecidFilter: String?) -> FBFuture<FBDeviceSet> {
  return FBFuture<AnyObject>.onQueue(
    DispatchQueue.main,
    resolveValue: { errorPtr -> AnyObject? in
      do {
        // Give a more meaningful message if we can't load the frameworks.
        try FBDeviceControlFrameworkLoader().loadPrivateFrameworks(logger)
        return try FBDeviceSet(logger: logger, delegate: nil, ecidFilter: ecidFilter)
      } catch {
        errorPtr?.pointee = error as NSError
        return nil
      }
    }
  ).delay(0.2) as! FBFuture<FBDeviceSet> // This is needed to give the Restorable Devices time to populate.
}

private func defaultTargetSets(_ userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<NSArray> {
  let only = userDefaults.string(forKey: "-only")
  if let only {
    if only.lowercased().contains("simulator") {
      logger.log("'--only' set for Simulators")
      return allFutures([simulatorSet(userDefaults, logger: logger, reporter: reporter)])
    }
    if only.lowercased().contains("device") {
      logger.log("'--only' set for Devices")
      return allFutures([deviceSet(logger, ecidFilter: nil)])
    }
    if only.lowercased().hasPrefix("ecid:") {
      let ecid = only.lowercased().replacingOccurrences(of: "ecid:", with: "")
      logger.log("ECID filter of \(ecid)")
      return allFutures([deviceSet(logger, ecidFilter: ecid)])
    }
    return unsafeBitCast(FBIDBError.describe("\(only) is not a valid argument for '--only'").failFuture() as FBFuture<AnyObject>, to: FBFuture<NSArray>.self)
  }
  if !xcodeAvailable {
    logger.log("Xcode is not available, only Devices will be provided")
    return allFutures([deviceSet(logger, ecidFilter: nil)])
  }
  logger.log("Providing targets across Simulator and Device sets.")
  return allFutures([
    simulatorSet(userDefaults, logger: logger, reporter: reporter),
    deviceSet(logger, ecidFilter: nil),
  ])
}

private func targetForUDID(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, warmUp: Bool, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<AnyObject> {
  return defaultTargetSets(userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter)
    .onQueue(
      DispatchQueue.main,
      fmap: { (targetSets: NSArray) -> FBFuture<AnyObject> in
        let sets = targetSets as! [FBiOSTargetSet]
        return FBiOSTargetProvider.target(withUDID: udid, targetSets: sets, warmUp: warmUp, logger: logger)
      })
}

private func deviceForECID(_ ecid: String, logger: FBControlCoreLogger) -> FBFuture<FBDevice> {
  return (deviceSet(logger, ecidFilter: ecid.replacingOccurrences(of: "ecid:", with: "")) as FBFuture)
    .onQueue(
      DispatchQueue.main,
      fmap: { (deviceSetObj: AnyObject) -> FBFuture<AnyObject> in
        let devSet = deviceSetObj as! FBDeviceSet
        let devices = devSet.allDevices
        if devices.isEmpty {
          return FBIDBError.describe("No devices \(FBCollectionInformation.oneLineDescription(from: devices)) matching \(ecid)").failFuture()
        }
        return FBFuture(result: devices[0])
      }) as! FBFuture<FBDevice>
}

private func simulatorFuture(_ udid: String, userDefaults: UserDefaults, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<FBSimulator> {
  return (simulatorSet(userDefaults, logger: logger, reporter: reporter) as FBFuture)
    .onQueue(
      DispatchQueue.main,
      fmap: { (setObj: AnyObject) -> FBFuture<AnyObject> in
        let simSet = setObj as! FBSimulatorSet
        return FBiOSTargetProvider.target(withUDID: udid, targetSets: [simSet], warmUp: false, logger: logger)
      }
    )
    .onQueue(
      DispatchQueue.main,
      fmap: { (targetObj: AnyObject) -> FBFuture<AnyObject> in
        guard let commands = targetObj as? FBSimulatorLifecycleCommandsProtocol else {
          return FBIDBError.describe("\(targetObj) does not support Simulator Lifecycle commands").failFuture()
        }
        return FBFuture(result: commands as AnyObject)
      }) as! FBFuture<FBSimulator>
}

private func targetOfflineFuture(_ target: FBiOSTarget, logger: FBControlCoreLogger) -> FBFuture<NSNull> {
  return target.resolveLeavesState(.booted)
    .onQueue(
      target.workQueue,
      doOnResolved: { (_: AnyObject) in
        target.logger?.log("Target is no longer booted, companion going offline")
      })
}

private func bootFuture(_ udid: String, userDefaults: UserDefaults, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<FBFuture<NSNull>> {
  let headless = userDefaults.bool(forKey: "-headless")
  let verifyBooted = userDefaults.object(forKey: "-verify-booted") == nil ? true : userDefaults.bool(forKey: "-verify-booted")
  return (simulatorFuture(udid, userDefaults: userDefaults, logger: logger, reporter: reporter) as FBFuture)
    .onQueue(
      DispatchQueue.main,
      fmap: { (simObj: AnyObject) -> FBFuture<AnyObject> in
        let simulator = simObj as! FBSimulator
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
        return simulator.boot(config).mapReplace(simulator)
      }
    )
    .onQueue(
      DispatchQueue.main,
      map: { (simObj: AnyObject) -> AnyObject in
        let simulator = simObj as! FBSimulator
        // Write the boot success to stdout
        writeTargetToStdOut(simulator)
        // In a headless boot:
        // - We need to keep this process running until it's otherwise shutdown. When the sim is shutdown this process will die.
        // - If this process is manually killed then the simulator will die
        // For a regular boot the sim will outlive this process.
        if !headless {
          return FBFuture<NSNull>.empty() as AnyObject
        }
        // Whilst we can rely on this process being killed shutting the simulator, this is asynchronous.
        // This means that we should attempt to handle cancellation gracefully.
        // In this case we should attempt to shutdown in response to cancellation.
        // This means if this future is cancelled and waited-for before the process exits we will return it in a "Shutdown" state.
        return targetOfflineFuture(simulator, logger: logger)
          .onQueue(
            DispatchQueue.main,
            respondToCancellation: {
              return simulator.shutdown()
            }) as AnyObject
      }) as! FBFuture<FBFuture<NSNull>>
}

private func shutdownFuture(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<NSNull> {
  return targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: false, logger: logger, reporter: reporter)
    .onQueue(
      DispatchQueue.main,
      fmap: { (targetObj: AnyObject) -> FBFuture<AnyObject> in
        guard let commands = targetObj as? FBPowerCommands else {
          return FBIDBError.describe("Cannot shutdown \(targetObj), does not support shutting down").failFuture()
        }
        return commands.shutdown() as! FBFuture<AnyObject>
      }) as! FBFuture<NSNull>
}

private func rebootFuture(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<NSNull> {
  return targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: false, logger: logger, reporter: reporter)
    .onQueue(
      DispatchQueue.main,
      fmap: { (targetObj: AnyObject) -> FBFuture<AnyObject> in
        guard let commands = targetObj as? FBPowerCommands else {
          return FBIDBError.describe("Cannot shutdown \(targetObj), does not support rebooting").failFuture()
        }
        return commands.reboot() as! FBFuture<AnyObject>
      }) as! FBFuture<NSNull>
}

private func eraseFuture(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<NSNull> {
  return targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: false, logger: logger, reporter: reporter)
    .onQueue(
      DispatchQueue.main,
      fmap: { (targetObj: AnyObject) -> FBFuture<AnyObject> in
        guard let commands = targetObj as? FBEraseCommands else {
          return FBIDBError.describe("Cannot erase \(targetObj), does not support erasing").failFuture()
        }
        return commands.erase() as! FBFuture<AnyObject>
      }) as! FBFuture<NSNull>
}

private func deleteFuture(_ udidOrAll: String, userDefaults: UserDefaults, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<NSNull> {
  return (simulatorSet(userDefaults, logger: logger, reporter: reporter) as FBFuture)
    .onQueue(
      DispatchQueue.main,
      fmap: { (setObj: AnyObject) -> FBFuture<AnyObject> in
        let set = setObj as! FBSimulatorSet
        if udidOrAll.lowercased() == "all" {
          return set.deleteAll() as! FBFuture<AnyObject>
        }
        guard let simulator = set.simulator(withUDID: udidOrAll) else {
          return FBIDBError.describe("Could not find a simulator with udid \(udidOrAll)").failFuture()
        }
        return set.delete(simulator) as! FBFuture<AnyObject>
      }
    )
    .mapReplace(NSNull()) as! FBFuture<NSNull>
}

private func listFuture(_ userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<NSNull> {
  return defaultTargetSets(userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter)
    .onQueue(
      DispatchQueue.main,
      map: { (targetSetsObj: AnyObject) -> AnyObject in
        let targetSets = targetSetsObj as! [FBiOSTargetSet]
        var reportedCount: UInt = 0
        for targetSet in targetSets {
          for targetInfo in targetSet.allTargetInfos {
            writeTargetToStdOut(targetInfo)
            reportedCount += 1
          }
        }
        logger.log("Reported \(reportedCount) targets to stdout")
        return NSNull()
      }) as! FBFuture<NSNull>
}

private func createFuture(_ create: String, userDefaults: UserDefaults, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<NSNull> {
  return (simulatorSet(userDefaults, logger: logger, reporter: reporter) as FBFuture)
    .onQueue(
      DispatchQueue.main,
      fmap: { (setObj: AnyObject) -> FBFuture<AnyObject> in
        let set = setObj as! FBSimulatorSet
        let parameters = create.components(separatedBy: ",")
        var config = FBSimulatorConfiguration.default
        if parameters.count > 0 {
          config = config.withDeviceModel(FBDeviceModel(rawValue: parameters[0]))
        }
        if parameters.count > 1 {
          config = config.withOSNamed(FBOSVersionName(rawValue: parameters[1]))
        }
        return set.createSimulator(with: config) as! FBFuture<AnyObject>
      }
    )
    .onQueue(
      DispatchQueue.main,
      map: { (simObj: AnyObject) -> AnyObject in
        let simulator = simObj as! FBSimulator
        writeTargetToStdOut(simulator)
        return NSNull()
      }) as! FBFuture<NSNull>
}

private func cloneFuture(_ udid: String, userDefaults: UserDefaults, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<NSNull> {
  let destinationSet = userDefaults.string(forKey: "-clone-destination-set")
  return allFutures([
    simulatorFuture(udid, userDefaults: userDefaults, logger: logger, reporter: reporter),
    simulatorSetWithPath(destinationSet, logger: logger, reporter: reporter),
  ])
  .onQueue(
    DispatchQueue.main,
    fmap: { (tuple: NSArray) -> FBFuture<AnyObject> in
      let base = tuple[0] as! FBSimulator
      let destination = tuple[1] as! FBSimulatorSet
      return base.set.cloneSimulator(base, toDeviceSet: destination) as! FBFuture<AnyObject>
    }
  )
  .onQueue(
    DispatchQueue.main,
    map: { (clonedObj: AnyObject) -> AnyObject in
      let cloned = clonedObj as! FBSimulator
      writeTargetToStdOut(cloned)
      return NSNull()
    }) as! FBFuture<NSNull>
}

private func enterRecoveryFuture(_ ecid: String, logger: FBControlCoreLogger) -> FBFuture<NSNull> {
  return (deviceForECID(ecid, logger: logger) as FBFuture)
    .onQueue(
      DispatchQueue.main,
      fmap: { (deviceObj: AnyObject) -> FBFuture<AnyObject> in
        let device = deviceObj as! FBDevice
        return device.enterRecovery() as! FBFuture<AnyObject>
      }) as! FBFuture<NSNull>
}

private func exitRecoveryFuture(_ ecid: String, logger: FBControlCoreLogger) -> FBFuture<NSNull> {
  return (deviceForECID(ecid, logger: logger) as FBFuture)
    .onQueue(
      DispatchQueue.main,
      fmap: { (deviceObj: AnyObject) -> FBFuture<AnyObject> in
        let device = deviceObj as! FBDevice
        return device.exitRecovery() as! FBFuture<AnyObject>
      }) as! FBFuture<NSNull>
}

private func activateFuture(_ ecid: String, logger: FBControlCoreLogger) -> FBFuture<NSNull> {
  return (deviceForECID(ecid, logger: logger) as FBFuture)
    .onQueue(
      DispatchQueue.main,
      fmap: { (deviceObj: AnyObject) -> FBFuture<AnyObject> in
        let device = deviceObj as! FBDevice
        return device.activate() as! FBFuture<AnyObject>
      }) as! FBFuture<NSNull>
}

private func cleanFuture(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<NSNull> {
  return targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: true, logger: logger, reporter: reporter)
    .onQueue(
      DispatchQueue.main,
      fmap: { (targetObj: AnyObject) -> FBFuture<AnyObject> in
        let target = targetObj as! FBiOSTarget
        do {
          let idbLogger = logger as! FBIDBLogger
          let storageManager = try FBIDBStorageManager.manager(forTarget: target, logger: idbLogger)
          let commandExecutor = FBIDBCommandExecutor.commandExecutor(
            forTarget: target,
            storageManager: storageManager,
            temporaryDirectory: FBTemporaryDirectory(logger: idbLogger),
            debugserverPort: in_port_t(IDBPortsConfiguration(arguments: userDefaults).debugserverPort),
            logger: idbLogger
          )
          return commandExecutor.clean() as! FBFuture<AnyObject>
        } catch {
          return FBFuture(error: error)
        }
      }) as! FBFuture<NSNull>
}

private func companionServerFuture(_ udid: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<FBFuture<NSNull>> {
  let terminateOffline = userDefaults.bool(forKey: "-terminate-offline")

  return targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: true, logger: logger, reporter: reporter)
    .onQueue(
      DispatchQueue.main,
      fmap: { (targetObj: AnyObject) -> FBFuture<AnyObject> in
        let target = targetObj as! FBiOSTarget
        let addMetadataSel = NSSelectorFromString("addMetadata:")
        if (reporter as AnyObject).responds(to: addMetadataSel) {
          _ = (reporter as AnyObject).perform(
            addMetadataSel,
            with: [
              "udid": udid,
              "target_type": FBiOSTargetTypeStringFromTargetType(target.targetType).lowercased(),
            ])
        }
        reporter.report(FBEventReporterSubject(forEvent: "launched"))

        let idbLogger = logger as! FBIDBLogger
        let temporaryDirectory = FBTemporaryDirectory(logger: idbLogger)

        do {
          let storageManager = try FBIDBStorageManager.manager(forTarget: target, logger: idbLogger)

          // Start up the companion
          let ports = IDBPortsConfiguration(arguments: userDefaults)

          // Command Executor
          let commandExecutor = FBIDBCommandExecutor.commandExecutor(
            forTarget: target,
            storageManager: storageManager,
            temporaryDirectory: temporaryDirectory,
            debugserverPort: in_port_t(ports.debugserverPort),
            logger: idbLogger
          )

          let loggingCommandExecutor = FBLoggingWrapper.wrap(commandExecutor, simplifiedNaming: true, eventReporter: IDBConfiguration.eventReporter, logger: logger)

          let swiftServer = try GRPCSwiftServer(
            target: target,
            commandExecutor: loggingCommandExecutor as! FBIDBCommandExecutor,
            reporter: IDBConfiguration.eventReporter,
            logger: logger as! FBIDBLogger,
            ports: ports
          )

          return (swiftServer.start() as FBFuture)
            .onQueue(
              target.workQueue,
              map: { (serverDescription: AnyObject) -> AnyObject in
                writeJSONToStdOut(serverDescription)
                var futures: [FBFuture<NSNull>] = [unsafeBitCast(swiftServer.completed, to: FBFuture<NSNull>.self)]

                if terminateOffline {
                  logger.info().log("Companion will terminate when target goes offline")
                  futures.append(targetOfflineFuture(target, logger: logger))
                } else {
                  logger.info().log("Companion will stay alive if target goes offline")
                }

                let completed = FBFuture(race: futures)
                return
                  completed
                  .onQueue(
                    target.workQueue,
                    chain: { (future: FBFuture<AnyObject>) -> FBFuture<AnyObject> in
                      temporaryDirectory.cleanOnExit()
                      return future
                    }) as AnyObject
              })
        } catch {
          return FBFuture(error: error)
        }
      }) as! FBFuture<FBFuture<NSNull>>
}

private func notiferFuture(_ notify: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<FBFuture<NSNull>> {
  return defaultTargetSets(userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter)
    .onQueue(
      DispatchQueue.main,
      fmap: { (targetSetsObj: AnyObject) -> FBFuture<AnyObject> in
        let targetSets = targetSetsObj as! [FBiOSTargetSet]
        if notify == "stdout" {
          return FBiOSTargetStateChangeNotifier.notifierToStdOut(withTargetSets: targetSets, logger: logger) as! FBFuture<AnyObject>
        }
        return FBiOSTargetStateChangeNotifier.notifierToFilePath(notify, withTargetSets: targetSets, logger: logger) as! FBFuture<AnyObject>
      }
    )
    .onQueue(
      DispatchQueue.main,
      fmap: { (notifierObj: AnyObject) -> FBFuture<AnyObject> in
        let notifier = notifierObj as! FBiOSTargetStateChangeNotifier
        logger.log("Starting Notifier \(notifier)")
        return (notifier.startNotifier() as FBFuture).mapReplace(notifier)
      }
    )
    .onQueue(
      DispatchQueue.main,
      map: { (notifierObj: AnyObject) -> AnyObject in
        let notifier = notifierObj as! FBiOSTargetStateChangeNotifier
        logger.log("Started Notifier \(notifier)")
        return notifier.notifierDone
          .onQueue(
            DispatchQueue.main,
            respondToCancellation: {
              logger.log("Stopping Notifier \(notifier)")
              return FBFuture<NSNull>.empty()
            }) as AnyObject
      }) as! FBFuture<FBFuture<NSNull>>
}

private func forwardFuture(_ forward: String, userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger, reporter: FBEventReporter) -> FBFuture<NSNull> {
  let components = forward.components(separatedBy: ":")
  if components.count != 2 {
    return unsafeBitCast(FBIDBError.describe("\(forward) should be of the form UDID:PORT").failFuture() as FBFuture<AnyObject>, to: FBFuture<NSNull>.self)
  }
  let udid = components[0]
  let remotePort = Int32(components[1]) ?? 0

  return targetForUDID(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, warmUp: false, logger: logger, reporter: reporter)
    .onQueue(
      DispatchQueue.main,
      fmap: { (targetObj: AnyObject) -> FBFuture<AnyObject> in
        guard let commands = targetObj as? FBSocketForwardingCommands else {
          return FBIDBError.describe("\(targetObj) does not conform to FBSocketForwardingCommands").failFuture()
        }
        return commands.drainLocalFileInput(STDIN_FILENO, localFileOutput: STDOUT_FILENO, remotePort: remotePort) as! FBFuture<AnyObject>
      }) as! FBFuture<NSNull>
}

private func getCompanionCompletedFuture(_ userDefaults: UserDefaults, xcodeAvailable: Bool, logger: FBControlCoreLogger) -> FBFuture<FBFuture<NSNull>> {
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
    return companionServerFuture(udid, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter)
  } else if list != nil {
    logger.info().log("Listing")
    return FBFuture(result: listFuture(userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter))
  } else if let notify {
    logger.info().log("Notifying \(notify)")
    return notiferFuture(notify, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter)
  } else if let boot {
    logger.log("Booting \(boot)")
    return bootFuture(boot, userDefaults: userDefaults, logger: logger, reporter: reporter)
  } else if let shutdown {
    logger.info().log("Shutting down \(shutdown)")
    return FBFuture(result: shutdownFuture(shutdown, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter))
  } else if let reboot {
    logger.info().log("Rebooting \(reboot)")
    return FBFuture(result: rebootFuture(reboot, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter))
  } else if let erase {
    logger.info().log("Erasing \(erase)")
    return FBFuture(result: eraseFuture(erase, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter))
  } else if let deleteArg {
    logger.info().log("Deleting \(deleteArg)")
    return FBFuture(result: deleteFuture(deleteArg, userDefaults: userDefaults, logger: logger, reporter: reporter))
  } else if let create {
    logger.info().log("Creating \(create)")
    return FBFuture(result: createFuture(create, userDefaults: userDefaults, logger: logger, reporter: reporter))
  } else if let clone {
    logger.info().log("Cloning \(clone)")
    return FBFuture(result: cloneFuture(clone, userDefaults: userDefaults, logger: logger, reporter: reporter))
  } else if let recover {
    logger.info().log("Putting \(recover) into recovery")
    return FBFuture(result: enterRecoveryFuture(recover, logger: logger))
  } else if let unrecover {
    logger.info().log("Removing \(unrecover) from recovery")
    return FBFuture(result: exitRecoveryFuture(unrecover, logger: logger))
  } else if let activate {
    logger.info().log("Activating \(activate)")
    return FBFuture(result: activateFuture(activate, logger: logger))
  } else if let clean {
    logger.info().log("Cleaning \(clean)")
    return FBFuture(result: cleanFuture(clean, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter))
  } else if let forward {
    logger.info().log("Forwarding \(forward)")
    return FBFuture(result: forwardFuture(forward, userDefaults: userDefaults, xcodeAvailable: xcodeAvailable, logger: logger, reporter: reporter))
  }
  return unsafeBitCast(FBIDBError.describe("You must specify at least one 'Mode of operation'\n\n\(kUsageHelpMessage)").failFuture() as FBFuture<AnyObject>, to: FBFuture<FBFuture<NSNull>>.self)
}

private func signalHandlerFuture(_ signalCode: UInt, exitMessage: String, logger: FBControlCoreLogger) -> FBFuture<NSNumber> {
  let queue = DispatchQueue.global(qos: .userInitiated)
  let future: FBMutableFuture<NSNumber> = FBMutableFuture<NSNumber>()
  let source = DispatchSource.makeSignalSource(signal: Int32(signalCode), queue: DispatchQueue.main)
  source.setEventHandler {
    logger.error().log(exitMessage)
    future.resolve(withResult: NSNumber(value: signalCode))
  }
  source.resume()
  var action = sigaction()
  action.__sigaction_u.__sa_handler = SIG_IGN
  sigaction(Int32(signalCode), &action, nil)
  return unsafeBitCast(
    future
      .onQueue(
        queue,
        notifyOfCompletion: { (_: FBFuture<AnyObject>) in
          source.cancel()
        }), to: FBFuture<NSNumber>.self)
}

private func envDescription() -> String {
  return FBCollectionInformation.oneLineDescription(from: FBControlCoreGlobalConfiguration.safeSubprocessEnvironment)
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
  logger.info().log("Invoked with args=\(FBCollectionInformation.oneLineDescription(from: ProcessInfo.processInfo.arguments)) env=\(envDescription())")
}

private func idbMain() -> Int32 {
  let arguments = ProcessInfo.processInfo.arguments
  if arguments.contains("--help") {
    fputs(kUsageHelpMessage, stderr)
    return 1
  }
  if arguments.contains("--version") {
    writeJSONToStdOut(["build_time": kBuildTime, "build_date": kBuildDate])
    return 0
  }

  let userDefaults = UserDefaults.standard
  let logger = FBIDBLogger.logger(withUserDefaults: userDefaults)
  logStartupInfo(logger)

  // Check that xcode-select returns a valid path, exit with error if not found
  let xcodeAvailable = (try? FBXcodeDirectory.xcodeSelectDeveloperDirectory().`await`()) != nil
  if !xcodeAvailable {
    logger.error().log("Xcode developer directory not found. idb_companion requires Xcode to be installed and selected via xcode-select")
    return 1
  }

  let signalled = FBFuture(race: [
    signalHandlerFuture(UInt(SIGINT), exitMessage: "Signalled: SIGINT", logger: logger),
    signalHandlerFuture(UInt(SIGTERM), exitMessage: "Signalled: SIGTERM", logger: logger),
  ])
  let companionCompletedFuture = unsafeBitCast(getCompanionCompletedFuture(userDefaults, xcodeAvailable: xcodeAvailable, logger: logger), to: FBFuture<AnyObject>.self)
  guard let companionCompleted = try? companionCompletedFuture.`await`() as? FBFuture<NSNull> else {
    logger.error().log("Failed to get companion completed future")
    return 1
  }

  let completed = FBFuture(race: [
    unsafeBitCast(companionCompleted, to: FBFuture<AnyObject>.self),
    unsafeBitCast(signalled, to: FBFuture<AnyObject>.self),
  ])
  if let completedError = completed.error {
    logger.error().log(completedError.localizedDescription)
    return 1
  }
  guard let result = try? completed.`await`() else {
    logger.error().log("Companion completed with error")
    return 1
  }
  if companionCompleted.state == FBFutureState.cancelled {
    logger.log("Responding to termination of idb with signo \(result)")
    let cancellation = companionCompleted.cancel()
    guard let _ = try? cancellation.`await`() else {
      logger.error().log("Cancellation failed")
      return 1
    }
  }
  return 0
}

exit(autoreleasepool { idbMain() })
