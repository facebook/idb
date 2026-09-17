/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import Testing

@Suite("SimulatorSet logger retention")
struct SimulatorSetLoggerTests {

  private static func makeSet(logger: (any ControlCoreLogger)?) -> SimulatorSet {
    let deviceType = SimDeviceTypeDouble()
    deviceType.name = "iPhone 8"
    let runtime = SimDeviceRuntimeDouble()
    runtime.name = "iOS 15.0"
    runtime.versionString = "15.0"
    let device = SimDeviceDouble()
    device.name = "iPhone 8"
    device.deviceType = deviceType
    device.runtime = runtime
    let deviceSet = SimDeviceSetDouble()
    deviceSet.availableDevices = [device]
    let configuration = SimulatorControlConfiguration(deviceSetPath: nil, logger: nil)
    return createSimulatorSet(configuration: configuration, fakeDeviceSet: deviceSet, logger: logger)
  }

  @Test("A nil logger is defaulted at the factory boundary")
  func nilLoggerIsDefaulted() {
    let set = Self.makeSet(logger: nil)
    #expect(set.logger === ControlCoreGlobalConfiguration.defaultLogger)
    #expect(set.allSimulators.first?.logger != nil)
  }

  @Test("An explicit logger is retained")
  func explicitLoggerIsRetained() {
    let logger = ControlCoreGlobalConfiguration.defaultLogger.withName("logger-pin")
    let set = Self.makeSet(logger: logger)
    #expect(set.logger === logger)
  }
}
