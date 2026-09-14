/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class SimulatorRuntimeResolutionTests: XCTestCase {
  private let device = SimulatorRuntimeIndex.Device(identifier: "future.device", name: "Future Device")

  private func runtime(
    identifier: String = "future.runtime", name: String = "FutureOS 99.0",
    version: String = "99.0", build: String = "99A100", available: Bool = true,
    supportedDevices: Set<String> = ["future.device"]
  ) -> SimulatorRuntimeIndex.Runtime {
    SimulatorRuntimeIndex.Runtime(
      identifier: identifier, name: name, version: version, build: build,
      available: available, supportedDevices: supportedDevices)
  }

  private func resolve(
    _ runtimes: [SimulatorRuntimeIndex.Runtime], runtime selector: SimulatorSelector? = .name("FutureOS 99.0")
  ) throws -> SimulatorRuntimeIndex.Runtime {
    let index = SimulatorRuntimeIndex(devices: [device], runtimes: runtimes)
    let match = try index.resolve(device: .name(device.name), runtime: selector)
    return index.runtimes[match.runtime]
  }

  func testUncataloguedDeviceAndRuntimeResolve() throws {
    XCTAssertEqual(try resolve([runtime()]).identifier, "future.runtime")
  }

  func testNoMatchingRuntimeThrows() {
    XCTAssertThrowsError(try resolve([runtime(name: "OtherOS 99.0")]))
  }

  func testUnavailableRuntimeDoesNotMatch() {
    XCTAssertThrowsError(try resolve([runtime(available: false)]))
  }

  func testIncompatibleDeviceDoesNotMatch() {
    XCTAssertThrowsError(try resolve([runtime(supportedDevices: ["another.device"])]))
  }

  func testMultipleBuildsChooseNewestRegardlessOfInputOrder() throws {
    let older = runtime(build: "99A9")
    let newer = runtime(build: "99A100")
    XCTAssertEqual(try resolve([older, newer]).build, newer.build)
    XCTAssertEqual(try resolve([newer, older]).build, newer.build)
  }

  func testUnavailableOrIncompatibleNewerBuildDoesNotHideUsableBuild() throws {
    let usable = runtime(build: "99A9")
    XCTAssertEqual(try resolve([usable, runtime(build: "99A100", available: false)]).build, usable.build)
    XCTAssertEqual(try resolve([usable, runtime(build: "99A100", supportedDevices: [])]).build, usable.build)
  }

  func testLatestFiltersBeforeOrderingVersionComponents() throws {
    let expected = runtime(identifier: "chosen", name: "FutureOS 99.10.1", version: "99.10.1")
    let runtimes = [
      runtime(version: "99.9"), runtime(version: "99.10"), expected,
      runtime(version: "100.0", available: false), runtime(version: "101.0", supportedDevices: []),
    ]
    XCTAssertEqual(try resolve(runtimes, runtime: nil).identifier, expected.identifier)
    XCTAssertEqual(try resolve(Array(runtimes.reversed()), runtime: nil).identifier, expected.identifier)
  }

  func testExplicitRuntimeDoesNotFallBackToNewest() {
    XCTAssertThrowsError(try resolve([runtime(name: "FutureOS 100.0", version: "100.0")]))
  }

  func testRuntimeIdentifierSelectsAmongEqualNames() throws {
    let other = runtime(identifier: "another.runtime", build: "99A999")
    XCTAssertEqual(try resolve([other, runtime()], runtime: .identifier("future.runtime")).identifier, "future.runtime")
  }

  func testIdentifierDoesNotFallBackToDisplayName() {
    XCTAssertThrowsError(try resolve([runtime(name: "missing.runtime")], runtime: .identifier("missing.runtime")))
  }

  func testAmbiguousDeviceNameRequiresIdentifier() throws {
    let duplicateName = SimulatorRuntimeIndex.Device(identifier: "another.device", name: device.name)
    let index = SimulatorRuntimeIndex(devices: [duplicateName, device], runtimes: [runtime()])
    XCTAssertThrowsError(try index.resolve(device: .name(device.name), runtime: nil))
    let match = try index.resolve(device: .identifier(device.identifier), runtime: nil)
    XCTAssertEqual(index.devices[match.device].identifier, device.identifier)
  }

  func testEmptyIndexFailsClearly() {
    let index = SimulatorRuntimeIndex(devices: [], runtimes: [])
    XCTAssertThrowsError(try index.resolve(device: .name(device.name), runtime: nil))
  }
}
