/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import XCTest

private class BundleFinder {}

enum TestFixtures {

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

  static let simulatorAppCrashWithJSONFormat = Bundle(for: BundleFinder.self)
    .path(forResource: "replhost-simulator-crash", ofType: "ips")!

  static let photo0Path = Bundle(for: BundleFinder.self)
    .path(forResource: "photo0", ofType: "png")!

  static let simulatorSystemLogPath = Bundle(for: BundleFinder.self)
    .path(forResource: "simulator_system", ofType: "log")!

  static let treeJSONPath = Bundle(for: BundleFinder.self)
    .path(forResource: "tree", ofType: "json")!

  static let probeLeaksPath = Bundle(for: BundleFinder.self)
    .path(forResource: "probe_leaks", ofType: "txt")!

  static let probeHeapPath = Bundle(for: BundleFinder.self)
    .path(forResource: "probe_heap", ofType: "txt")!

  static let probeSamplePath = Bundle(for: BundleFinder.self)
    .path(forResource: "probe_sample", ofType: "txt")!

  static let probeVmmapPath = Bundle(for: BundleFinder.self)
    .path(forResource: "probe_vmmap", ofType: "txt")!

  static let probeFootprintPath = Bundle(for: BundleFinder.self)
    .path(forResource: "probe_footprint", ofType: "json")!

  static let bundleResource = Bundle(for: BundleFinder.self).resourcePath!
}

extension XCTestCase {

  /// Returns the process info for the current process (equivalent to launchctl).
  func launchCtlProcess() -> RunningProcessInfo? {
    return ProcessFetcher().processInfo(for: ProcessInfo.processInfo.processIdentifier)
  }
}
