/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import Foundation
import Testing

/// The restorable device's tolerant reads: restore info dictionaries are populated by MobileDevice
/// and may omit keys or carry unexpectedly-typed values, so every accessor must degrade to the
/// unknown value rather than trap.
@Suite
struct FBAMRestorableDeviceTests {

  private func device(allValues: [String: Any]) -> FBAMRestorableDevice {
    FBAMRestorableDevice(
      calls: FBCreateZeroedAMDCalls(),
      restorableDevice: "fake-restorable-ref" as AnyObject,
      allValues: allValues,
      work: DispatchQueue(label: "com.facebook.fbdevicecontrol.tests.work"),
      asyncQueue: DispatchQueue(label: "com.facebook.fbdevicecontrol.tests.async"),
      logger: FBControlCoreGlobalConfiguration.defaultLogger)
  }

  @Test
  func stringProductTypeFlowsIntoDeviceType() {
    #expect(device(allValues: [FBDeviceKey.productType.rawValue: "iPhone14,2"]).deviceType.model.rawValue == "iPhone14,2")
  }

  @Test
  func stringDeviceNameFlowsIntoName() {
    #expect(device(allValues: [FBDeviceKey.deviceName.rawValue: "lab-device"]).name == "lab-device")
  }

  @Test
  func numericUniqueChipIDFlowsIntoUniqueIdentifier() {
    #expect(device(allValues: [FBDeviceKey.uniqueChipID.rawValue: 12345]).uniqueIdentifier == "12345")
  }

  @Test
  func missingDeviceNameFallsBackToUnknown() {
    #expect(device(allValues: [:]).name == "unknown")
  }

  @Test
  func missingUniqueChipIDFallsBackToUnknown() {
    #expect(device(allValues: [:]).uniqueIdentifier == "unknown")
  }

  @Test
  func missingProductTypeFallsBackToUnknownDeviceType() {
    #expect(device(allValues: [:]).deviceType.model.rawValue == "unknown")
  }

  @Test
  func nonStringProductTypeFallsBackToUnknownDeviceType() {
    #expect(device(allValues: [FBDeviceKey.productType.rawValue: 42]).deviceType.model.rawValue == "unknown")
  }

  @Test
  func stringUniqueChipIDFlowsIntoUniqueIdentifier() {
    #expect(device(allValues: [FBDeviceKey.uniqueChipID.rawValue: "chip-as-string"]).uniqueIdentifier == "chip-as-string")
  }

  @Test
  func nonStringDeviceNameFallsBackToUnknown() {
    #expect(device(allValues: [FBDeviceKey.deviceName.rawValue: 99]).name == "unknown")
  }
}
