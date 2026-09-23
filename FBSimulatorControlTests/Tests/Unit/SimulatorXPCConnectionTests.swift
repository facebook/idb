/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

/// The one place a host connection into a booted simulator is built, and how each transport reads
/// its failures. The success path needs a live simulator and is exercised by the smoke suites.
final class SimulatorXPCConnectionTests: XCTestCase {

  private static let unsupported = NSError(domain: "com.apple.CoreSimulator.SimError", code: 405)
  private static let operational = NSError(domain: "com.apple.CoreSimulator.SimError", code: 165)

  private func connect(_ error: NSError?) -> SimulatorXPCConnectionError? {
    do {
      _ = try SimulatorXPCConnection.connect(service: "com.example.service") { _ in (mach_port_t(MACH_PORT_NULL), error) }
      return nil
    } catch let error as SimulatorXPCConnectionError {
      return error
    } catch {
      XCTFail("Unexpected error: \(error)")
      return nil
    }
  }

  func testAFailedLookupCarriesTheServiceAndTheUnderlyingError() {
    XCTAssertEqual(connect(Self.operational), .lookupFailed(service: "com.example.service", underlying: Self.operational))
    XCTAssertEqual(connect(nil), .lookupFailed(service: "com.example.service", underlying: nil))
  }

  func testOnlySimError405MeansTheServiceIsUnsupported() {
    XCTAssertEqual(connect(Self.unsupported)?.isServiceUnsupported, true)
    XCTAssertEqual(connect(Self.operational)?.isServiceUnsupported, false)
    XCTAssertEqual(connect(nil)?.isServiceUnsupported, false)
    XCTAssertFalse(SimulatorXPCConnectionError.symbolsUnavailable.isServiceUnsupported)
    XCTAssertFalse(SimulatorXPCConnectionError.connectionFailed.isServiceUnsupported)
  }

  // MARK: - CoreDevice mapping

  func testCoreDeviceTreatsAnUnsupportedServiceAndMissingSymbolsAsMissingCapabilities() {
    let unsupported = SimulatorCoreDeviceError(connection: .lookupFailed(service: "com.example.service", underlying: Self.unsupported))
    guard case let .unsupported(detail) = unsupported else { return XCTFail("\(unsupported)") }
    XCTAssertEqual(detail, "com.example.service")

    guard case .unsupported = SimulatorCoreDeviceError(connection: .symbolsUnavailable) else {
      return XCTFail("Missing symbols should read as unsupported")
    }
  }

  func testCoreDeviceTreatsOtherConnectionFailuresAsUnavailable() {
    for error: SimulatorXPCConnectionError in [
      .lookupFailed(service: "com.example.service", underlying: Self.operational),
      .lookupFailed(service: "com.example.service", underlying: nil),
      .connectionFailed,
    ] {
      guard case .unavailable = SimulatorCoreDeviceError(connection: error) else { return XCTFail("\(error)") }
    }
  }

  // MARK: - DTUHID mapping

  func testDTUHIDKeepsItsOwnCasesSoNegotiationIsUnchanged() {
    let lookup = SimulatorHIDError(dtuhidConnection: .lookupFailed(service: "com.example.service", underlying: Self.operational))
    guard case let .dtuhidServiceUnavailable(name, underlying) = lookup else { return XCTFail("\(lookup)") }
    XCTAssertEqual(name, "com.example.service")
    XCTAssertEqual(underlying as NSError?, Self.operational)
    XCTAssertTrue(lookup.isTransientDTUHIDFailure)
    XCTAssertTrue(lookup.isDTUHIDUnreachable)

    let symbols = SimulatorHIDError(dtuhidConnection: .symbolsUnavailable)
    guard case .dtuhidXPCSymbolsUnavailable = symbols else { return XCTFail("\(symbols)") }
    XCTAssertFalse(symbols.isTransientDTUHIDFailure)
    XCTAssertTrue(symbols.isDTUHIDUnreachable)

    let connection = SimulatorHIDError(dtuhidConnection: .connectionFailed)
    guard case .dtuhidConnectionFailed = connection else { return XCTFail("\(connection)") }
    XCTAssertTrue(connection.isTransientDTUHIDFailure)
  }
}
