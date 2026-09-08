/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

/// The entry point to a simulator device set: loads the private frameworks, opens the service
/// context and vends the `FBSimulatorSet`. Named distinctly from the module on purpose: a type
/// that shares its module's name shadows the module in qualified lookups and cannot be emitted
/// into a module interface.
public final class SimulatorControlBootstrap {

  public var configuration: FBSimulatorControlConfiguration
  public let serviceContext: FBSimulatorServiceContext
  public let set: FBSimulatorSet

  public class func withConfiguration(_ configuration: FBSimulatorControlConfiguration) throws -> SimulatorControlBootstrap {
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(configuration.logger)
    let serviceContext = try FBSimulatorServiceContext.sharedServiceContext(withLogger: configuration.logger)
    let deviceSet = try serviceContext.createDeviceSet(with: configuration)
    let set = try FBSimulatorSet.set(
      withConfiguration: configuration,
      deviceSet: deviceSet,
      delegate: nil,
      logger: configuration.logger.withName("simulator_set"))
    return SimulatorControlBootstrap(configuration: configuration, serviceContext: serviceContext, set: set)
  }

  private init(configuration: FBSimulatorControlConfiguration, serviceContext: FBSimulatorServiceContext, set: FBSimulatorSet) {
    self.configuration = configuration
    self.serviceContext = serviceContext
    self.set = set
  }
}
