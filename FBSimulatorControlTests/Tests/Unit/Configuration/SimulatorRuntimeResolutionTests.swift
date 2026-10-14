/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

@Suite
struct SimulatorRuntimeResolutionTests {
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
    let match = try index.resolve(SimulatorCreationRequest(device: .name(device.name), runtime: selector))
    return index.runtimes[match.runtime]
  }

  @Test
  func uncataloguedDeviceAndRuntimeResolve() throws {
    #expect(try resolve([runtime()]).identifier == "future.runtime")
  }

  @Test
  func noMatchingRuntimeThrows() {
    #expect(throws: (any Error).self) { try resolve([runtime(name: "OtherOS 99.0")]) }
  }

  @Test
  func unavailableRuntimeDoesNotMatch() {
    #expect(throws: (any Error).self) { try resolve([runtime(available: false)]) }
  }

  @Test
  func incompatibleDeviceDoesNotMatch() {
    #expect(throws: (any Error).self) { try resolve([runtime(supportedDevices: ["another.device"])]) }
  }

  @Test
  func multipleBuildsChooseNewestRegardlessOfInputOrder() throws {
    let older = runtime(build: "99A9")
    let newer = runtime(build: "99A100")
    #expect(try resolve([older, newer]).build == newer.build)
    #expect(try resolve([newer, older]).build == newer.build)
    #expect(try resolve([older, newer], runtime: .identifier(newer.identifier)).build == newer.build)
    #expect(try resolve([newer, older], runtime: .identifier(newer.identifier)).build == newer.build)
  }

  @Test
  func unavailableOrIncompatibleNewerBuildDoesNotHideUsableBuild() throws {
    let usable = runtime(build: "99A9")
    #expect(try resolve([usable, runtime(build: "99A100", available: false)]).build == usable.build)
    #expect(try resolve([usable, runtime(build: "99A100", supportedDevices: [])]).build == usable.build)
  }

  @Test
  func latestFiltersBeforeOrderingVersionComponents() throws {
    let expected = runtime(identifier: "chosen", name: "FutureOS 99.10.1", version: "99.10.1")
    let runtimes = [
      runtime(version: "99.9"), runtime(version: "99.10"), expected,
      runtime(version: "100.0", available: false), runtime(version: "101.0", supportedDevices: []),
    ]
    #expect(try resolve(runtimes, runtime: nil).identifier == expected.identifier)
    #expect(try resolve(Array(runtimes.reversed()), runtime: nil).identifier == expected.identifier)
  }

  @Test
  func explicitRuntimeDoesNotFallBackToNewest() {
    #expect(throws: (any Error).self) { try resolve([runtime(name: "FutureOS 100.0", version: "100.0")]) }
  }

  @Test
  func runtimeIdentifierSelectsAmongEqualNames() throws {
    let other = runtime(identifier: "another.runtime", build: "99A999")
    #expect(try resolve([other, runtime()], runtime: .identifier("future.runtime")).identifier == "future.runtime")
  }

  @Test
  func identifierDoesNotFallBackToDisplayName() {
    #expect(throws: (any Error).self) { try resolve([runtime(name: "missing.runtime")], runtime: .identifier("missing.runtime")) }
  }

  @Test
  func ambiguousDeviceNameRequiresIdentifier() throws {
    let duplicateName = SimulatorRuntimeIndex.Device(identifier: "another.device", name: device.name)
    let index = SimulatorRuntimeIndex(devices: [duplicateName, device], runtimes: [runtime()])
    #expect(throws: (any Error).self) { try index.resolve(SimulatorCreationRequest(device: .name(device.name))) }
    let match = try index.resolve(SimulatorCreationRequest(device: .identifier(device.identifier)))
    #expect(index.devices[match.device].identifier == device.identifier)
  }

  @Test
  func discoveryIncludesOnlyAvailableCompatiblePairs() {
    let other = SimulatorRuntimeIndex.Device(identifier: "other.device", name: "Other Device")
    let index = SimulatorRuntimeIndex(
      devices: [device, other], runtimes: [runtime(), runtime(available: false), runtime(supportedDevices: [])])
    #expect(index.availablePairs == [SimulatorRuntimeIndex.Match(device: 0, runtime: 0)])
  }

  @Test
  func emptyIndexFailsClearly() {
    let index = SimulatorRuntimeIndex(devices: [], runtimes: [])
    #expect(throws: (any Error).self) { try index.resolve(SimulatorCreationRequest(device: .name(device.name))) }
  }
}
