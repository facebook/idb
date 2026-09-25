/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Testing

@Suite("HID transport selection")
struct SimulatorHIDTransportSelectionTests {

  // MARK: - CoreSimulator version gate

  @Test(
    "dtuhidd ships from CoreSimulator-1155.4",
    arguments: [
      (nil, false),
      ("1140.0", false),
      ("1155.3", false),
      ("1155.4", true),
      ("1169.1", true),
    ] as [(String?, Bool)])
  func shipsDTUHID(version: String?, expected: Bool) {
    #expect(SimulatorHIDTransportSelection.shipsDTUHID(coreSimulatorVersion: version) == expected)
  }

  @Test("CoreSimulator versions compare numerically, not lexicographically")
  func shipsDTUHIDComparesNumerically() {
    // A lexicographic compare puts "1155.10" below "1155.4" and "999.9" above it.
    #expect(SimulatorHIDTransportSelection.shipsDTUHID(coreSimulatorVersion: "1155.10"))
    #expect(!SimulatorHIDTransportSelection.shipsDTUHID(coreSimulatorVersion: "999.9"))
  }

  // MARK: - DTUHID reachability

  @Test("Only a failure to reach dtuhidd is worth falling back to Indigo for")
  func isDTUHIDUnreachable() {
    #expect(SimulatorHIDError.dtuhidXPCSymbolsUnavailable.isDTUHIDUnreachable)
    #expect(SimulatorHIDError.dtuhidDigitizerServiceUnavailable(underlying: nil).isDTUHIDUnreachable)
    #expect(SimulatorHIDError.dtuhidConnectionFailed.isDTUHIDUnreachable)
  }

  @Test("A fault in an established transport is not a reachability failure")
  func isDTUHIDUnreachableRejectsOtherFailures() {
    #expect(!SimulatorHIDError.clientDisposed.isDTUHIDUnreachable)
    #expect(!SimulatorHIDError.simulatorKitUnavailable.isDTUHIDUnreachable)
    #expect(!SimulatorHIDError.notImplementedOnDTUHIDTransport(operation: "trackpad pan").isDTUHIDUnreachable)
    #expect(!SimulatorHIDError.touchUnsupportedOnAppleTV.isDTUHIDUnreachable)
  }

  // MARK: - Legacy keyboard suppression

  @Test("A toolchain without dtuhidd never suppresses the legacy keyboard")
  func legacyKeyboardIsNotSuppressedBeforeXcode27() {
    #expect(!SimulatorHIDTransportSelection.isLegacyKeyboardSuppressed(coreSimulatorVersion: "1140.0"))
  }

  @Test("A toolchain that ships dtuhidd suppresses the legacy keyboard")
  func legacyKeyboardIsSuppressedFromXcode27() {
    #expect(SimulatorHIDTransportSelection.isLegacyKeyboardSuppressed(coreSimulatorVersion: "1169.1"))
  }

  // MARK: - Default transport

  @Test("A toolchain without dtuhidd gets the legacy Indigo transport")
  func defaultTransportBeforeXcode27() {
    #expect(SimulatorHIDTransportSelection.defaultTransport(coreSimulatorVersion: "1140.0") == .indigo)
  }

  @Test("A toolchain that ships dtuhidd gets the DTUHID transport")
  func defaultTransportFromXcode27() {
    #expect(SimulatorHIDTransportSelection.defaultTransport(coreSimulatorVersion: "1169.1") == .dtuhid)
  }
}
