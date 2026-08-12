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
struct FBSimulatorHIDTransportSelectionTests {

  // MARK: CoreSimulator version gate

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
    #expect(FBSimulatorHIDTransportSelection.shipsDTUHID(coreSimulatorVersion: version) == expected)
  }

  @Test("CoreSimulator versions compare numerically, not lexicographically")
  func shipsDTUHIDComparesNumerically() {
    // A lexicographic compare puts "1155.10" below "1155.4" and "999.9" above it.
    #expect(FBSimulatorHIDTransportSelection.shipsDTUHID(coreSimulatorVersion: "1155.10"))
    #expect(!FBSimulatorHIDTransportSelection.shipsDTUHID(coreSimulatorVersion: "999.9"))
  }

  // MARK: Product family

  @Test(
    "Every family but Apple TV can be driven over DTUHID",
    arguments: [
      (FBControlCoreProductFamily.familyiPhone, true),
      (.familyiPad, true),
      (.familyAppleWatch, true),
      (.familyAppleTV, false),
    ])
  func supportsDTUHID(family: FBControlCoreProductFamily, expected: Bool) {
    #expect(FBSimulatorHIDTransportSelection.supportsDTUHID(productFamily: family) == expected)
  }

  // MARK: DTUHID reachability

  @Test("Only a failure to reach dtuhidd is worth falling back to Indigo for")
  func isDTUHIDUnreachable() {
    #expect(FBSimulatorHIDError.dtuhidXPCSymbolsUnavailable.isDTUHIDUnreachable)
    #expect(FBSimulatorHIDError.dtuhidDigitizerServiceUnavailable(underlying: nil).isDTUHIDUnreachable)
    #expect(FBSimulatorHIDError.dtuhidConnectionFailed.isDTUHIDUnreachable)
  }

  @Test("A fault in an established transport is not a reachability failure")
  func isDTUHIDUnreachableRejectsOtherFailures() {
    #expect(!FBSimulatorHIDError.clientDisposed.isDTUHIDUnreachable)
    #expect(!FBSimulatorHIDError.simulatorKitUnavailable.isDTUHIDUnreachable)
    #expect(!FBSimulatorHIDError.notImplementedOnDTUHIDTransport(operation: "trackpad pan").isDTUHIDUnreachable)
    #expect(!FBSimulatorHIDError.touchUnsupportedOnAppleTV.isDTUHIDUnreachable)
  }

  // MARK: Legacy HID suppression

  @Test("A toolchain without dtuhidd never suppresses the legacy HID")
  func legacyHIDIsNotSuppressedBeforeXcode27() {
    #expect(
      !FBSimulatorHIDTransportSelection.isLegacyHIDSuppressed(
        coreSimulatorVersion: "1140.0", isDTUHIDDRunning: { true }))
  }

  @Test("A running dtuhidd suppresses the legacy HID")
  func legacyHIDIsSuppressedWithDTUHIDDRunning() {
    #expect(
      FBSimulatorHIDTransportSelection.isLegacyHIDSuppressed(
        coreSimulatorVersion: "1169.1", isDTUHIDDRunning: { true }))
  }

  @Test("A dtuhidd that is not currently running does not suppress the legacy HID")
  func legacyHIDIsNotSuppressedWithDTUHIDDStopped() {
    // BUG: reports the legacy HID as healthy whenever `dtuhidd` is not resident, but `dtuhidd` is
    // demand-launched and pressured-exit, so it is normally *not* running on a CoreSimulator that
    // suppresses the legacy HID unconditionally — flipped in the following commit.
    #expect(
      !FBSimulatorHIDTransportSelection.isLegacyHIDSuppressed(
        coreSimulatorVersion: "1169.1", isDTUHIDDRunning: { false }))
  }

  // MARK: Default transport

  @Test("A toolchain without dtuhidd gets the legacy Indigo transport")
  func defaultTransportBeforeXcode27() {
    #expect(
      FBSimulatorHIDTransportSelection.defaultTransport(
        coreSimulatorVersion: "1140.0", isDTUHIDDRunning: { false }) == .indigo)
  }

  @Test("A running dtuhidd gets the DTUHID transport")
  func defaultTransportWithDTUHIDDRunning() {
    #expect(
      FBSimulatorHIDTransportSelection.defaultTransport(
        coreSimulatorVersion: "1169.1", isDTUHIDDRunning: { true }) == .dtuhid)
  }

  @Test("A dtuhidd that is not currently running gets the legacy Indigo transport")
  func defaultTransportWithDTUHIDDStopped() {
    // BUG: hands back the legacy Indigo transport, which delivers nothing at all on
    // CoreSimulator-1155.4+ — touch, buttons and keyboard are all silently dropped. `dtuhidd` being
    // idle says nothing about whether it can be reached — flipped in the following commit.
    #expect(
      FBSimulatorHIDTransportSelection.defaultTransport(
        coreSimulatorVersion: "1169.1", isDTUHIDDRunning: { false }) == .indigo)
  }
}
