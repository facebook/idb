/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

@objc(FBAppleSimctlCommandExecutor)
public final class FBAppleSimctlCommandExecutor: NSObject {

  // MARK: - Properties

  private let deviceSetPath: String
  private let deviceUUID: String?
  private let queue: DispatchQueue
  private let logger: any FBControlCoreLogger

  // MARK: - Initializers

  @objc(executorForSimulator:)
  public class func executor(for simulator: FBSimulator) -> FBAppleSimctlCommandExecutor {
    return FBAppleSimctlCommandExecutor(
      deviceSetPath: simulator.set.deviceSet.setPath,
      deviceUUID: simulator.udid,
      logger: simulator.logger!.withName("simctl"))
  }

  @objc(executorForDeviceSet:)
  public class func executor(for set: FBSimulatorSet) -> FBAppleSimctlCommandExecutor {
    return FBAppleSimctlCommandExecutor(
      deviceSetPath: set.deviceSet.setPath,
      deviceUUID: nil,
      logger: set.logger!)
  }

  private init(deviceSetPath: String, deviceUUID: String?, logger: any FBControlCoreLogger) {
    self.deviceSetPath = deviceSetPath
    self.deviceUUID = deviceUUID
    self.logger = logger
    self.queue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.simctl_executor")
    super.init()
  }

  // MARK: - Public Methods

  @objc(taskBuilderWithCommand:arguments:)
  public func taskBuilder(withCommand command: String, arguments: [String]) -> FBProcessBuilder<NSNull, FBControlCoreLogger, FBControlCoreLogger> {
    var derived: [String] = [
      "simctl",
      "--set",
      deviceSetPath,
      command,
    ]
    if let deviceUUID = deviceUUID {
      derived.append(deviceUUID)
    }
    derived.append(contentsOf: arguments)

    return FBProcessBuilder<NSNull, FBControlCoreLogger, FBControlCoreLogger>
      .withLaunchPath("/usr/bin/xcrun", arguments: derived)
      .withStdOut(to: logger)
      .withStdErr(to: logger)
  }
}
