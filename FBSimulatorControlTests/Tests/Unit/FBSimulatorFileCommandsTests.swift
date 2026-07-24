/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// A `SimDevice` stand-in that returns a canned `installedApps()` dictionary, letting the
/// container-selection producers be exercised without a booted simulator. `FBSimulator`'s
/// initializer only reads `device.UDID.UUIDString`, so `UDID` plus `installedAppsWithError:`
/// is the whole surface these tests touch.
private final class InstalledAppsStubDevice: NSObject {
  @objc let UDID = NSUUID()
  private let apps: [String: Any]

  init(apps: [String: Any]) {
    self.apps = apps
    super.init()
  }

  @objc(installedAppsWithError:)
  func installedApps() throws -> [String: Any] {
    apps
  }
}

/// Locks the container path-mapping behavior of `FBSimulatorFileCommands`. These assertions
/// hold identically against the pre-conversion `FBFutureContext` producers and the async
/// producers — the `withFileCommandsFor…` API is unchanged — so they prove the async
/// conversion is behavior-preserving.
final class FBSimulatorFileCommandsTests: XCTestCase {

  private func makeSimulator(installedApps: [String: Any]) -> FBSimulator {
    FBSimulatorTestSupport.testableSimulator(withDevice: InstalledAppsStubDevice(apps: installedApps))
  }

  func testApplicationContainersMapsDataContainerPathsAndSkipsAppsWithout() async throws {
    let simulator = makeSimulator(installedApps: [
      "com.example.app1": ["DataContainer": URL(fileURLWithPath: "/data/app1")],
      "com.example.app2": ["DataContainer": URL(fileURLWithPath: "/data/app2")],
      "com.example.nodata": ["SomeOtherKey": "ignored"],
    ])

    let mapping = try await simulator.withFileCommandsForApplicationContainers { $0.pathMapping }

    XCTAssertEqual(mapping, ["com.example.app1": "/data/app1", "com.example.app2": "/data/app2"])
  }

  func testGroupContainersMergesGroupPathsAcrossApps() async throws {
    let simulator = makeSimulator(installedApps: [
      "com.example.app1": ["GroupContainers": ["group.a": URL(fileURLWithPath: "/groups/a")]],
      "com.example.app2": ["GroupContainers": ["group.b": URL(fileURLWithPath: "/groups/b")]],
      "com.example.nogroups": ["DataContainer": URL(fileURLWithPath: "/data/nogroups")],
    ])

    let mapping = try await simulator.withFileCommandsForGroupContainers { $0.pathMapping }

    XCTAssertEqual(mapping, ["group.a": "/groups/a", "group.b": "/groups/b"])
  }
}
