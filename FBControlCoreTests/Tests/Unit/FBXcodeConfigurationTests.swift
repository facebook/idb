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
}
