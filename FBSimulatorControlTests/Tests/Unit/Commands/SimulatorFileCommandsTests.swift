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

/// A `SimDevice` stand-in that returns a canned `installedApps()` dictionary, letting the
/// container-selection producers be exercised without a booted simulator. `Simulator`'s
/// initializer only reads `device.UDID.UUIDString`, so `UDID` plus `installedAppsWithError:`
/// is the whole surface these tests touch.
private final class InstalledAppsStubDevice {
  @objc let UDID = NSUUID()
  private let apps: [String: Any]

  init(apps: [String: Any]) {
    self.apps = apps
  }

  @objc(installedAppsWithError:)
  func installedApps() throws -> [String: Any] {
    apps
  }
}

/// Locks the container path-mapping behaviour of `SimulatorFileCommands`.
@Suite
struct SimulatorFileCommandsTests {

  private func makeSimulator(installedApps: [String: Any]) -> Simulator {
    SimulatorTestSupport.testableSimulator(withDevice: InstalledAppsStubDevice(apps: installedApps))
  }

  @Test
  func applicationContainersMapsDataContainerPathsAndSkipsAppsWithout() async throws {
    let simulator = makeSimulator(installedApps: [
      "com.example.app1": ["DataContainer": URL(fileURLWithPath: "/data/app1")],
      "com.example.app2": ["DataContainer": URL(fileURLWithPath: "/data/app2")],
      "com.example.nodata": ["SomeOtherKey": "ignored"],
    ])

    let mapping = try await simulator.file.withApplicationContainers { $0.pathMapping }

    #expect(mapping == ["com.example.app1": "/data/app1", "com.example.app2": "/data/app2"])
  }

  @Test
  func groupContainersMergesGroupPathsAcrossApps() async throws {
    let simulator = makeSimulator(installedApps: [
      "com.example.app1": ["GroupContainers": ["group.a": URL(fileURLWithPath: "/groups/a")]],
      "com.example.app2": ["GroupContainers": ["group.b": URL(fileURLWithPath: "/groups/b")]],
      "com.example.nogroups": ["DataContainer": URL(fileURLWithPath: "/data/nogroups")],
    ])

    let mapping = try await simulator.file.withGroupContainers { $0.pathMapping }

    #expect(mapping == ["group.a": "/groups/a", "group.b": "/groups/b"])
  }
}
