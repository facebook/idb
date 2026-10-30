/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import Testing
import XPC

/// The Apple Watch side button over the DTUHID digitizer transport, against a synthetic service.
@Suite
struct SimulatorWatchButtonTests {

  private struct NoSleep: DTUHIDSleeper {
    func sleep(for duration: Duration) async throws {}
  }

  private actor Connections {
    let services = SyntheticXPCServices()
    let peer: SyntheticXPCPeer

    init() {
      peer = services.register(SimulatorDigitizerHIDTransport.serviceName) { request in
        guard xpc_dictionary_get_bool(request.message, "isBarrier") else { return }
        request.reply(xpc_dictionary_create(nil, nil, 0))
      }
    }

    func connect() async throws -> SimulatorDTUHIDConnection {
      try await SimulatorDTUHIDConnection.connect(
        using: services.connector,
        serviceName: SimulatorDigitizerHIDTransport.serviceName,
        sleeper: NoSleep())
    }
  }

  private func transport(
    _ connections: Connections, family: ProductFamily
  ) async throws -> SimulatorDigitizerHIDTransport {
    SimulatorDigitizerHIDTransport(
      connection: try await connections.connect(),
      mainScreenSize: CGSize(width: 208, height: 248),
      mainScreenScale: 2,
      productFamily: family)
  }

  /// Consumer page 0x0C, usage 0x95, as a down then an up.
  @Test
  func aSidePressIsSerializedAsItsConsumerUsage() async throws {
    let connections = Connections()
    let digitizer = try await transport(connections, family: .appleWatch)
    try await digitizer.sendWatchButton(direction: .down, button: .side)
    try await digitizer.sendWatchButton(direction: .up, button: .side)
    let received = await connections.peer.received(atLeast: 3)
    let payloads =
      received
      .filter { !xpc_dictionary_get_bool($0, "isBarrier") }
      .compactMap { xpc_dictionary_get_value($0, "payload") }

    #expect(
      received.dropFirst().map { xpc_dictionary_get_string($0, "messageType").map { String(cString: $0) } }
        == ["IndigoButtonEvent", "IndigoButtonEvent"])
    #expect(payloads.map { xpc_dictionary_get_uint64($0, "usagePage") } == [0x0C, 0x0C])
    #expect(payloads.map { xpc_dictionary_get_uint64($0, "usageCode") } == [0x95, 0x95])
    #expect(payloads.map { xpc_dictionary_get_uint64($0, "state") } == [1, 2])
    digitizer.disconnect()
  }

  /// Every other family is refused, so the Watch vocabulary cannot be aimed at an iPhone.
  @Test(arguments: [ProductFamily.iPhone, .iPad, .appleTV, .mac, .unknown])
  func aTargetWithoutTheButtonIsRejected(_ family: ProductFamily) async throws {
    let connections = Connections()
    let digitizer = try await transport(connections, family: family)
    await #expect {
      try await digitizer.sendWatchButton(direction: .down, button: .side)
    } throws: { error in
      guard case let .watchButtonUnsupportedOnProductFamily(_, reported) = error as? SimulatorHIDError else { return false }
      return reported == family
    }
    digitizer.disconnect()
  }

  /// The generic iPhone vocabulary is untouched: `sideButton` there is still Consumer Power, and
  /// is a different thing from the Watch's side button.
  @Test
  func theGenericSideButtonKeepsItsPowerUsage() {
    #expect(SimulatorHIDButton.sideButton.identity.consumerUsage?.page == 0x0C)
    #expect(SimulatorHIDButton.sideButton.identity.consumerUsage?.code == 0x30)
    #expect(SimulatorWatchButton.side.consumerUsage != (page: 0x0C, code: 0x30))
  }

  @Test
  func aShortPressIsADownThenAnUp() throws {
    let children = try #require(SimulatorHIDEvent.shortWatchButtonPress(.side).subEvents)
    #expect(
      children == [
        .watchButton(direction: .down, button: .side),
        .watchButton(direction: .up, button: .side),
      ])
  }
}
