/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

@objc(FBSimulatorProcessSpawnCommands)
public final class FBSimulatorProcessSpawnCommands: NSObject, FBProcessSpawnCommands {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorProcessSpawnCommands {
    return FBSimulatorProcessSpawnCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBProcessSpawnCommands Implementation

  @objc
  public func launchProcess(_ configuration: FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    guard let simulator = simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>
    }
    return (unsafeBitCast(configuration.io.attach(), to: FBFuture<AnyObject>.self)
      .onQueue(simulator.workQueue, fmap: { (attachmentObj: AnyObject) -> FBFuture<AnyObject> in
        let attachment = attachmentObj as! FBProcessIOAttachment
        return unsafeBitCast(
          FBSimulatorProcessSpawnCommands.launchProcess(
            withSimulator: simulator,
            configuration: configuration,
            attachment: attachment
          ),
          to: FBFuture<AnyObject>.self
        )
      })) as! FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>
  }

  // MARK: - Public

  @objc(launchOptionsWithArguments:environment:waitForDebugger:)
  public class func launchOptions(withArguments arguments: [String], environment: [String: String], waitForDebugger: Bool) -> [String: Any] {
    var options: [String: Any] = [:]
    options["arguments"] = arguments
    options["environment"] = environment
    if waitForDebugger {
      options["wait_for_debugger"] = NSNumber(value: 1)
    }
    return options
  }

  // MARK: - Private

  private class func launchProcess(withSimulator simulator: FBSimulator, configuration: FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>, attachment: FBProcessIOAttachment) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    let logger = simulator.logger
    let launchFuture = FBMutableFuture<NSNumber>(name: "Launch of \(configuration.launchPath) on \(simulator.udid)")
    let statLoc = FBMutableFuture<NSNumber>(name: "Process completion of \(configuration.launchPath) on \(simulator.udid)")
    let exitCode = FBMutableFuture<NSNumber>(name: "Process exit of \(configuration.launchPath) on \(simulator.udid)")
    let signal = FBMutableFuture<NSNumber>(name: "Process signal of \(configuration.launchPath) on \(simulator.udid)")

    let options = simDeviceLaunchOptions(
      withSimulator: simulator,
      launchPath: configuration.launchPath,
      arguments: configuration.arguments,
      environment: configuration.environment,
      waitForDebugger: false,
      stdOut: attachment.stdOut,
      stdErr: attachment.stdErr,
      mode: configuration.mode
    )

    FBSimDeviceWrapper.spawnAsync(
      onDevice: simulator.device,
      path: configuration.launchPath,
      options: options,
      terminationQueue: simulator.workQueue,
      terminationHandler: { (statLocValue: Int32) in
        FBProcessSpawnCommandHelpers.resolveProcessFinished(
          withStatLoc: statLocValue,
          inTeardownOfIOAttachment: attachment,
          statLocFuture: statLoc,
          exitCodeFuture: exitCode,
          signalFuture: signal,
          processIdentifier: Int32(truncatingIfNeeded: launchFuture.result?.intValue ?? 0),
          configuration: configuration,
          queue: simulator.workQueue,
          logger: logger
        )
        attachment.stdOut?.close()
        attachment.stdErr?.close()
      },
      completionQueue: simulator.workQueue,
      completionHandler: { (error: Error?, processIdentifier: Int32) in
        if let error = error {
          launchFuture.resolveWithError(error)
        } else {
          launchFuture.resolve(withResult: NSNumber(value: processIdentifier))
        }
      }
    )

    return ((launchFuture as FBFuture<AnyObject>)
      .onQueue(simulator.workQueue, map: { (processIdentifierNumber: AnyObject) -> AnyObject in
        let processIdentifier = (processIdentifierNumber as! NSNumber).int32Value
        return FBSubprocess<AnyObject, AnyObject, AnyObject>(
          processIdentifier: processIdentifier,
          statLoc: unsafeBitCast(statLoc, to: FBFuture<NSNumber>.self),
          exitCode: unsafeBitCast(exitCode, to: FBFuture<NSNumber>.self),
          signal: unsafeBitCast(signal, to: FBFuture<NSNumber>.self),
          configuration: configuration,
          queue: simulator.workQueue
        )
      })) as! FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>
  }

  private class func simDeviceLaunchOptions(withSimulator simulator: FBSimulator, launchPath: String, arguments: [String], environment: [String: String], waitForDebugger: Bool, stdOut: FBProcessStreamAttachment?, stdErr: FBProcessStreamAttachment?, mode: FBProcessSpawnMode) -> [String: Any] {
    // argv[0] should be launch path of the process. SimDevice does not do this automatically, so we need to add it.
    let fullArguments = [launchPath] + arguments
    var options = launchOptions(withArguments: fullArguments, environment: environment, waitForDebugger: waitForDebugger)
    if let stdOut = stdOut {
      options["stdout"] = NSNumber(value: stdOut.fileDescriptor)
    }
    if let stdErr = stdErr {
      options["stderr"] = NSNumber(value: stdErr.fileDescriptor)
    }
    options["standalone"] = NSNumber(value: shouldLaunchStandalone(onSimulator: simulator, mode: mode))
    return options
  }

  private class func shouldLaunchStandalone(onSimulator simulator: FBSimulator, mode: FBProcessSpawnMode) -> Bool {
    switch mode {
    case .launchd:
      return false
    case .posixSpawn:
      return true
    default:
      // Default behaviour is to use launchd if booted, otherwise use standalone.
      return simulator.state != .booted
    }
  }
}
