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

@objc private final class MetadataDeviceType: NSObject {
  @objc let name = "Future Device"
  @objc let identifier = "future.device"
  @objc let productFamilyID: Int32 = 42
}

@objc private final class MetadataRuntime: NSObject {
  @objc let name = "Future Platform"
  @objc let identifier = "future.runtime"
  @objc let versionString = "99.10.2"
  @objc let buildVersionString = "99A100"
}

@objc private final class MetadataSimDevice: NSObject {
  @objc let deviceType = MetadataDeviceType()
  @objc let runtime = MetadataRuntime()
}

@Suite
struct SimulatorMetadataTests {
  @Test
  func missingMetadataRemainsDescribable() {
    let configuration = SimulatorConfiguration.configuration(deviceType: nil, runtime: nil)
    #expect(configuration.device.model.rawValue == "unknown")
    #expect(configuration.os.versionString == "")
    #expect(configuration.runtimeIdentifier == nil)
  }

  @Test
  func differentVersionsWithoutIdentifiersRemainDistinct() {
    let device = DeviceType.generic(withName: "Future Device")
    let name = OSVersionName(rawValue: "Future Platform")
    let first = SimulatorConfiguration(device: device, os: OSVersion(name: name, versionString: "99.0"))
    let second = SimulatorConfiguration(device: device, os: OSVersion(name: name, versionString: "100.0"))
    #expect(Set([first, second]).count == 2)
  }

  @Test
  func runtimeIdentifierPreservesIdentityAcrossDisplayNameChanges() {
    let device = DeviceType.generic(withName: "Future Device")
    let first = SimulatorConfiguration(device: device, os: .generic(withName: "FutureOS 99.0"), runtimeIdentifier: "future.runtime")
    let second = SimulatorConfiguration(device: device, os: .generic(withName: "RenamedOS 99.0"), runtimeIdentifier: "future.runtime")
    #expect(Set([first, second]).count == 1)
  }

  @Test
  func differentBuildsRemainDistinct() {
    let device = DeviceType.generic(withName: "Future Device")
    let os = OSVersion.generic(withName: "FutureOS 99.0")
    let first = SimulatorConfiguration(device: device, os: os, runtimeIdentifier: "future.runtime", runtimeBuildVersion: "99A1")
    let second = SimulatorConfiguration(device: device, os: os, runtimeIdentifier: "future.runtime", runtimeBuildVersion: "99A2")
    #expect(Set([first, second]).count == 2)
  }

  @Test
  func uncataloguedSimulatorUsesReportedMetadata() {
    let configuration = SimulatorConfiguration.inferSimulatorConfiguration(
      fromDevice: SimulatorTestSupport.asDevice(MetadataSimDevice()))
    #expect(configuration.device.model.rawValue == "Future Device")
    #expect(configuration.os.name.rawValue == "Future Platform")
    #expect(configuration.os.version.majorVersion == 99)
    #expect(configuration.os.version.minorVersion == 10)
    #expect(configuration.device.family == .unknown)
    #expect(configuration.deviceTypeIdentifier == "future.device")
    #expect(configuration.runtimeIdentifier == "future.runtime")
    #expect(configuration.runtimeBuildVersion == "99A100")
  }
}
