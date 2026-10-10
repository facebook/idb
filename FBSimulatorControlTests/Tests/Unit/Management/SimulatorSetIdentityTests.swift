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

@Suite("SimulatorSet identity")
struct SimulatorSetIdentityTests {

  private static func makeDevice(udid: NSUUID = NSUUID(), available: Bool = true) -> SimDeviceDouble {
    let deviceType = SimDeviceTypeDouble()
    deviceType.name = "iPhone 8"
    let runtime = SimDeviceRuntimeDouble()
    runtime.name = "iOS 15.0"
    runtime.versionString = "15.0"
    let device = SimDeviceDouble()
    device.name = "iPhone 8"
    device.UDID = udid
    device.available = available
    device.deviceType = deviceType
    device.runtime = runtime
    return device
  }

  private static func makeSet(_ deviceSet: SimDeviceSetDouble) -> SimulatorSet {
    createSimulatorSet(configuration: SimulatorControlConfiguration(deviceSetPath: nil, logger: nil), fakeDeviceSet: deviceSet)
  }

  @Test func repeatedLookupReturnsTheSameInstance() {
    let device = Self.makeDevice()
    let deviceSet = SimDeviceSetDouble()
    deviceSet.devices = [Self.makeDevice(), device]
    let set = Self.makeSet(deviceSet)

    let first = set.simulator(withUDID: device.UDID.uuidString)
    let second = set.simulator(withUDID: device.UDID.uuidString)
    #expect(first != nil)
    #expect(first === second)
  }

  @Test func lookupAndEnumerationReturnTheSameInstance() {
    let device = Self.makeDevice()
    let deviceSet = SimDeviceSetDouble()
    deviceSet.devices = [device]
    let set = Self.makeSet(deviceSet)

    let looked = set.simulator(withUDID: device.UDID.uuidString)
    #expect(looked != nil)
    #expect(set.allSimulators.first === looked)
  }

  @Test func unavailableDevicesAreNotFound() {
    let unavailable = Self.makeDevice(available: false)
    let deviceSet = SimDeviceSetDouble()
    deviceSet.devices = [Self.makeDevice(), unavailable]
    let set = Self.makeSet(deviceSet)

    #expect(set.simulator(withUDID: unavailable.UDID.uuidString) == nil)
    #expect(set.allSimulators.count == 1)
  }

  @Test func deletedDevicesAreNoLongerFound() {
    let device = Self.makeDevice()
    let deviceSet = SimDeviceSetDouble()
    deviceSet.devices = [device]
    let set = Self.makeSet(deviceSet)
    #expect(set.simulator(withUDID: device.UDID.uuidString) != nil)

    deviceSet.devices = []
    #expect(set.simulator(withUDID: device.UDID.uuidString) == nil)
    #expect(set.allSimulators.isEmpty)
  }

  @Test func droppedSimulatorRetention() {
    let device = Self.makeDevice()
    let deviceSet = SimDeviceSetDouble()
    deviceSet.devices = [device]
    let set = Self.makeSet(deviceSet)

    weak var dropped: Simulator?
    autoreleasepool {
      dropped = set.simulator(withUDID: device.UDID.uuidString)
    }
    #expect(dropped != nil)
  }

  @Test func wrappersConstructedBySingleLookup() {
    let target = Self.makeDevice()
    let devices = [Self.makeDevice(), target, Self.makeDevice(), Self.makeDevice()]
    let deviceSet = SimDeviceSetDouble()
    deviceSet.devices = devices
    let set = Self.makeSet(deviceSet)

    _ = set.simulator(withUDID: target.UDID.uuidString)
    #expect(devices.map(\.deviceTypeReads).reduce(0, +) == 1)
  }

  @Test func vendedSimulatorCarriesTheSetsHIDEventLogging() {
    let device = Self.makeDevice()
    let deviceSet = SimDeviceSetDouble()
    deviceSet.devices = [device]
    let configuration = SimulatorControlConfiguration(deviceSetPath: nil, logger: nil, hidEventLogging: .detailed)
    let set = createSimulatorSet(configuration: configuration, fakeDeviceSet: deviceSet)

    #expect(set.simulator(withUDID: device.UDID.uuidString)?.hidEventLogging == .detailed)
    #expect(SimulatorTestSupport.testableSimulator().hidEventLogging == .redacted)
  }
}
