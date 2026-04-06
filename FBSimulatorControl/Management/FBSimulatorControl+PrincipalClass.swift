/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

@objc(FBSimulatorControl)
public final class FBSimulatorControl: NSObject {

  // MARK: - Properties

  @objc public var configuration: FBSimulatorControlConfiguration
  @objc public let serviceContext: FBSimulatorServiceContext
  @objc public let set: FBSimulatorSet

  // MARK: - Initializers

  @objc(withConfiguration:error:)
  public class func withConfiguration(_ configuration: FBSimulatorControlConfiguration) throws -> FBSimulatorControl {
    FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworksOrAbort()
    let serviceContext = FBSimulatorServiceContext.sharedServiceContext(withLogger: configuration.logger)
    let deviceSet = try serviceContext.createDeviceSet(with: configuration)
    let set = FBSimulatorSet.set(
      withConfiguration: configuration,
      deviceSet: deviceSet,
      delegate: nil,
      logger: configuration.logger.withName("simulator_set"),
      reporter: configuration.reporter)
    return FBSimulatorControl(configuration: configuration, serviceContext: serviceContext, set: set)
  }

  private init(configuration: FBSimulatorControlConfiguration, serviceContext: FBSimulatorServiceContext, set: FBSimulatorSet) {
    self.configuration = configuration
    self.serviceContext = serviceContext
    self.set = set
    super.init()
  }
}
