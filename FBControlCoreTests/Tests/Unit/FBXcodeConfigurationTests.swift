/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite struct FBXcodeConfigurationTests {

  private func writePlist(_ contents: [String: Any]) throws -> String {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FBXcodeConfigurationTests-\(UUID().uuidString).plist")
    try (contents as NSDictionary).write(to: URL(fileURLWithPath: path))
    return path
  }

  @Test func readsStringValueForPresentKey() throws {
    let path = try writePlist(["Version": "17.4"])
    let value = FBXcodeConfiguration.readValue(forKey: "Version", fromPlistAtPath: path)
    #expect(value as? String == "17.4")
  }

  @Test func readsNonStringValueForPresentKey() throws {
    let path = try writePlist(["ProjectName": "IDESimulatorAvailability", "Count": 3])
    let value = FBXcodeConfiguration.readValue(forKey: "Count", fromPlistAtPath: path)
    #expect((value as? NSNumber)?.intValue == 3)
  }

  @Test func returnsNilForMissingPlist() {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FBXcodeConfigurationTests-missing-\(UUID().uuidString).plist")
    let value = FBXcodeConfiguration.readValue(forKey: "Version", fromPlistAtPath: path)
    #expect(value == nil)
  }

  @Test func returnsNilForRelativePlistPathFromEmptyDeveloperDirectory() {
    // The path shape produced when the developer directory resolves to "" on hosts
    // without a full Xcode install.
    let value = FBXcodeConfiguration.readValue(forKey: "Version", fromPlistAtPath: "Platforms/iPhoneSimulator.platform/Info.plist")
    #expect(value == nil)
  }

  @Test func returnsNilForUnreadablePlist() throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FBXcodeConfigurationTests-garbage-\(UUID().uuidString).plist")
    try Data([0x00, 0x01, 0x02, 0x03]).write(to: URL(fileURLWithPath: path))
    let value = FBXcodeConfiguration.readValue(forKey: "Version", fromPlistAtPath: path)
    #expect(value == nil)
  }

  @Test func returnsNilForMissingKey() throws {
    let path = try writePlist(["Version": "17.4"])
    let value = FBXcodeConfiguration.readValue(forKey: "SomeOtherKey", fromPlistAtPath: path)
    #expect(value == nil)
  }
}
