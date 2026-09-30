/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Testing

@Suite("HID transport negotiation")
struct SimulatorHIDTransportNegotiationTests {

  /// Establishes the transport types in `reachable`, throwing `failure` for any other, and records
  /// every attempt in order.
  private final class Establisher {
    let reachable: Set<SimulatorHIDTransportType>
    let failure: SimulatorHIDError
    private(set) var attempts: [SimulatorHIDTransportType] = []

    init(reachable: Set<SimulatorHIDTransportType>, failure: SimulatorHIDError = .dtuhidConnectionFailed) {
      self.reachable = reachable
      self.failure = failure
    }

    func establish(_ type: SimulatorHIDTransportType) throws -> SimulatorHIDTransportType {
      attempts.append(type)
      guard reachable.contains(type) else {
        throw failure
      }
      return type
    }
  }

  @Test("A requested transport is established as-is", arguments: [SimulatorHIDTransportType.indigo, .dtuhid])
  func requestedTransportIsEstablished(requested: SimulatorHIDTransportType) async throws {
    let establisher = Establisher(reachable: [.indigo, .dtuhid])
    let transport = try await SimulatorHIDTransport.negotiate(requested: requested, preferred: .dtuhid, establish: establisher.establish)
    #expect(transport == requested)
    #expect(establisher.attempts == [requested])
  }

  @Test("An unreachable requested transport is never substituted")
  func requestedTransportIsNotSubstituted() async throws {
    let establisher = Establisher(reachable: [.indigo])
    await #expect(throws: SimulatorHIDError.self) {
      try await SimulatorHIDTransport.negotiate(requested: .dtuhid, preferred: .dtuhid, establish: establisher.establish)
    }
    #expect(establisher.attempts == [.dtuhid])
  }

  @Test("With no request, the preferred transport is established", arguments: [SimulatorHIDTransportType.indigo, .dtuhid])
  func preferredTransportIsEstablished(preferred: SimulatorHIDTransportType) async throws {
    let establisher = Establisher(reachable: [.indigo, .dtuhid])
    let transport = try await SimulatorHIDTransport.negotiate(requested: nil, preferred: preferred, establish: establisher.establish)
    #expect(transport == preferred)
    #expect(establisher.attempts == [preferred])
  }

  @Test("With no request, a fault other than an unreachable dtuhidd surfaces")
  func preferredTransportFaultSurfaces() async throws {
    let establisher = Establisher(reachable: [.indigo], failure: .dtuhidConnectionInvalidated(name: "service"))
    await #expect(throws: SimulatorHIDError.self) {
      try await SimulatorHIDTransport.negotiate(requested: nil, preferred: .dtuhid, establish: establisher.establish)
    }
    #expect(establisher.attempts == [.dtuhid])
  }

  @Test("With no request, an unreachable dtuhidd surfaces rather than falling back to Indigo")
  func unreachableDTUHID() async throws {
    let establisher = Establisher(reachable: [.indigo])
    let error = await #expect(throws: SimulatorHIDError.self) {
      try await SimulatorHIDTransport.negotiate(requested: nil, preferred: .dtuhid, establish: establisher.establish)
    }
    guard case .dtuhidConnectionFailed = error else {
      Issue.record("Unexpected error \(String(describing: error))")
      return
    }
    #expect(establisher.attempts == [.dtuhid])
  }
}
