/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

@objc(FBSimulatorProcessSpawnCommands)
public final class FBSimulatorProcessSpawnCommands: NSObject, FBiOSTargetCommand {

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

  // MARK: - FBProcessSpawnCommands (legacy FBFuture entry point)

  @objc
  public func launchProcess(_ configuration: FBProcessSpawnConfiguration) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    fbFutureFromAsync { [self] in
      try await launchProcessAsync(configuration)
    }
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

  fileprivate func launchProcessAsync(_ configuration: FBProcessSpawnConfiguration) async throws -> FBSubprocess<AnyObject, AnyObject, AnyObject> {
    guard let simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let attachment = try await bridgeFBFuture(configuration.io.attach())
    return try await FBSimulatorProcessSpawnCommands.launchProcessAsync(
      withSimulator: simulator,
      configuration: configuration,
      attachment: attachment
    )
  }

  private class func launchProcessAsync(withSimulator simulator: FBSimulator, configuration: FBProcessSpawnConfiguration, attachment: FBProcessIOAttachment) async throws -> FBSubprocess<AnyObject, AnyObject, AnyObject> {
    let logger = simulator.logger
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

    // PID is needed by the termination handler for logging; we populate the
    // holder once `spawnAsync` returns it. The terminationHandler will only be
    // invoked after the process exits, which strictly follows that return.
    let pidHolder = PIDHolder()
    let processIdentifier = try await FBSimDeviceWrapper.spawnAsync(
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
          processIdentifier: pidHolder.value,
          configuration: configuration,
          queue: simulator.workQueue,
          logger: logger
        )
        attachment.stdOut?.close()
        attachment.stdErr?.close()
      },
      completionQueue: simulator.workQueue
    )
    pidHolder.value = processIdentifier

    return FBSubprocess<AnyObject, AnyObject, AnyObject>(
      processIdentifier: processIdentifier,
      statLoc: unsafeBitCast(statLoc, to: FBFuture<NSNumber>.self),
      exitCode: unsafeBitCast(exitCode, to: FBFuture<NSNumber>.self),
      signal: unsafeBitCast(signal, to: FBFuture<NSNumber>.self),
      configuration: configuration,
      queue: simulator.workQueue
    )
  }

  /// Lets the termination handler reach the PID once it's known, since
  /// `spawnAsync` produces the PID after the handler is registered.
  private final class PIDHolder: @unchecked Sendable {
    var value: Int32 = 0
  }

  private class func simDeviceLaunchOptions(withSimulator simulator: FBSimulator, launchPath: String, arguments: [String], environment: [String: String], waitForDebugger: Bool, stdOut: FBProcessStreamAttachment?, stdErr: FBProcessStreamAttachment?, mode: FBProcessSpawnMode) -> [String: Any] {
    // argv[0] should be launch path of the process. SimDevice does not do this automatically, so we need to add it.
    let fullArguments = [launchPath] + arguments
    var options = launchOptions(withArguments: fullArguments, environment: environment, waitForDebugger: waitForDebugger)
    if let stdOut {
      options["stdout"] = NSNumber(value: stdOut.fileDescriptor)
    }
    if let stdErr {
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
