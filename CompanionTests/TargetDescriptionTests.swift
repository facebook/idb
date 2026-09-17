/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Companion
import FBControlCore
import Foundation
import Testing

private final class FutureTarget: TargetInfo {
  let uniqueIdentifier = "future-udid"
  let udid = "future-udid"
  let name = "My Simulator"
  let deviceType = DeviceType(model: FBDeviceModel(rawValue: "Future Device"), family: .familyUnknown)
  let architectures: [FBArchitecture] = []
  let osVersion = OSVersion(name: FBOSVersionName(rawValue: "FutureOS 99.10"), versionString: "99.10")
  let extendedInformation: [String: Any] = ["custom": "preserved"]
  let targetType: FBiOSTargetType = .simulator
  let state: FBiOSTargetState = .shutdown
}

struct TargetDescriptionTests {
  @Test
  func futureMetadataKeepsTheJSONContract() throws {
    let data = try JSONSerialization.data(withJSONObject: TargetDescription(target: FutureTarget()).asJSON)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
    #expect(
      json == [
        "udid": "future-udid", "name": "My Simulator", "model": "Future Device",
        "os_version": "FutureOS 99.10", "state": "Shutdown", "type": "Simulator", "custom": "preserved",
      ])
  }
}
