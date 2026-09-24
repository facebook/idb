/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@testable import FBSimulatorControl
import XCTest
import XPC

/// The vendor-defined transport connects once and keeps the connection. The connection names no
/// real service, so writes resolve locally and never reach a daemon.
final class SimulatorVendorHIDTransportTests: XCTestCase {

  private enum ConnectFailure: Error {
    case injected
  }

  private actor Connections {
    var attempts = 0
    var failNext = false

    func fail(_ fail: Bool) { failNext = fail }

    func connect() throws -> SimulatorDTUHIDTransport {
      attempts += 1
      if failNext { throw ConnectFailure.injected }
      let connection = xpc_connection_create("com.facebook.fbsimulatorcontrol.test.vendor", nil)
      xpc_connection_set_event_handler(connection) { _ in }
      xpc_connection_resume(connection)
      return SimulatorDTUHIDTransport(
        connection: connection,
        serviceName: SimulatorDTUHIDTransport.vendorDefinedServiceName,
        mainScreenSize: CGSize(width: 100, height: 200),
        mainScreenScale: 2.0,
        productFamily: .iPhone,
        clock: DTUHIDDrainClock(sleep: { _ in }, awaitBarrierReply: { _, _ in }))
    }
  }

  private func event() throws -> IndigoVendorDefinedEvent {
    try SimulatorHingeAngle(degrees: 90).vendorEvent()
  }

  func testTheConnectionIsEstablishedOnceAndReusedAcrossSends() async throws {
    let connections = Connections()
    let vendor = SimulatorVendorHIDTransport { try await connections.connect() }
    for _ in 0..<3 {
      try await vendor.send(event())
    }
    let attempts = await connections.attempts
    XCTAssertEqual(attempts, 1)
    await vendor.disconnect()
  }

  func testAFailedConnectionIsAttemptedAgainOnTheNextSend() async throws {
    let connections = Connections()
    await connections.fail(true)
    let vendor = SimulatorVendorHIDTransport { try await connections.connect() }
    do {
      try await vendor.send(event())
      XCTFail("Expected the injected failure")
    } catch ConnectFailure.injected {}
    await connections.fail(false)
    try await vendor.send(event())
    try await vendor.send(event())
    let attempts = await connections.attempts
    XCTAssertEqual(attempts, 2)
    await vendor.disconnect()
  }

  func testDisconnectingForgetsTheConnectionAndASendReconnects() async throws {
    let connections = Connections()
    let vendor = SimulatorVendorHIDTransport { try await connections.connect() }
    try await vendor.send(event())
    await vendor.disconnect()
    await vendor.disconnect()
    try await vendor.send(event())
    let attempts = await connections.attempts
    XCTAssertEqual(attempts, 2)
    await vendor.disconnect()
  }

  func testDisconnectingTheHIDCommandsDropsTheVendorConnection() async throws {
    let connections = Connections()
    let hid = SimulatorHIDCommands(simulator: nil, vendorDefined: SimulatorVendorHIDTransport { try await connections.connect() })
    try await hid.vendorDefined.send(event())
    await hid.disconnect()
    try await hid.vendorDefined.send(event())
    let attempts = await connections.attempts
    XCTAssertEqual(attempts, 2)
    await hid.disconnect()
  }

  func testConcurrentFirstSendsShareOneConnection() async throws {
    let connections = Connections()
    let vendor = SimulatorVendorHIDTransport { try await connections.connect() }
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<4 {
        group.addTask { try await vendor.send(try self.event()) }
      }
      try await group.waitForAll()
    }
    let attempts = await connections.attempts
    XCTAssertEqual(attempts, 1)
    await vendor.disconnect()
  }
}
