/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

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
}
