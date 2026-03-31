/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest

@testable import FBControlCore

private class BundleFinder {}

enum TestFixtures {

  static let xctestBinary = Bundle(for: BundleFinder.self)
    .path(forResource: "xctest", ofType: nil)!

  static let assetsdCrashPathWithCustomDeviceSet = Bundle(for: BundleFinder.self)
    .path(forResource: "assetsd_custom_set", ofType: "crash")!

  static let appCrashPathWithDefaultDeviceSet = Bundle(for: BundleFinder.self)
    .path(forResource: "app_default_set", ofType: "crash")!

  static let appCrashPathWithCustomDeviceSet = Bundle(for: BundleFinder.self)
    .path(forResource: "app_custom_set", ofType: "crash")!

  static let agentCrashPathWithCustomDeviceSet = Bundle(for: BundleFinder.self)
    .path(forResource: "agent_custom_set", ofType: "crash")!

  static let appCrashWithJSONFormat = Bundle(for: BundleFinder.self)
    .path(forResource: "xctest-concated-json-crash", ofType: "ips")!

  static let photo0Path = Bundle(for: BundleFinder.self)
    .path(forResource: "photo0", ofType: "png")!

  static let simulatorSystemLogPath = Bundle(for: BundleFinder.self)
    .path(forResource: "simulator_system", ofType: "log")!

  static let treeJSONPath = Bundle(for: BundleFinder.self)
    .path(forResource: "tree", ofType: "json")!

  static let bundleResource = Bundle(for: BundleFinder.self).resourcePath!
}

extension XCTestCase {

  /// Returns the process info for the current process (equivalent to launchctl).
  func launchCtlProcess() -> FBProcessInfo? {
    return FBProcessFetcher().processInfo(for: ProcessInfo.processInfo.processIdentifier)
  }
}
