/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
// Matches the existing XCTest-based FBSimulatorControl unit suite (FBSimulatorPurpleHIDTests et al.).
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

/// Byte-level coverage of the Indigo payloads produced by `FBSimulatorIndigoHID`.
/// Offsets are taken from `Source/PrivateHeaders/SimulatorApp/Indigo.h`. These tests
/// pin the wire format so the ObjC -> Swift migration of the builder is provably a no-op.
final class FBSimulatorIndigoHIDTests: XCTestCase {

  override class func setUp() {
    super.setUp()
    // FBSimulatorIndigoHID() dlopens SimulatorKit. Pre-load the private
    // frameworks with the default logger (CoreSimulator, then SimulatorKit) so that the
    // builder's internal load is a no-op — its nil-logger load path would otherwise crash
    // when it is the first loader call in a bare unit-test process.
    FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworksOrAbort()
    FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworksOrAbort()
  }

  // MARK: - Helpers

  private func makeIndigo() throws -> FBSimulatorIndigoHID {
    try FBSimulatorIndigoHID()
  }

  private func uint8(at offset: Int, in data: Data) -> UInt8 {
    data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt8.self) }
  }

  private func uint32(at offset: Int, in data: Data) -> UInt32 {
    data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
  }

  private func double(at offset: Int, in data: Data) -> Double {
    data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Double.self) }
  }

  /// Returns the payload bytes with the per-call `payload.timestamp` (mach_absolute_time,
  /// 8 bytes at offset 0x24) zeroed, so two payloads can be compared for structural equality.
  private func zeroingTimestamp(_ data: Data) -> [UInt8] {
    var bytes = [UInt8](data)
    for i in 0x24..<0x2C {
      bytes[i] = 0
    }
    return bytes
  }

  // MARK: - Touch

  func testTouchPayloadLayout() throws {
    let indigo = try makeIndigo()
    // 200x400 px @2x, point (50,100) -> ratio (0.5, 0.5).
    let data = indigo.touchScreenSize(CGSize(width: 200, height: 400), screenScale: 2, direction: .down, x: 50, y: 100)

    // sizeof(IndigoMessage) + sizeof(IndigoPayload) == 0x140.
    XCTAssertEqual(data.count, 320, "Touch message should be 320 bytes")
    // innerSize at 0x18 == sizeof(IndigoPayload) == 0x90.
    XCTAssertEqual(uint32(at: 0x18, in: data), 0x90, "innerSize should be sizeof(IndigoPayload)")
    // eventType byte at 0x1c == IndigoEventTypeTouch (2).
    XCTAssertEqual(uint8(at: 0x1c, in: data), 2, "eventType should be touch")
    // payload.field1 at 0x20 == 0x0b.
    XCTAssertEqual(uint32(at: 0x20, in: data), 0x0b, "payload.field1 should be 0x0b")
    // touch.xRatio at 0x3c, yRatio at 0x44.
    XCTAssertEqual(double(at: 0x3c, in: data), 0.5, accuracy: 1e-9, "xRatio")
    XCTAssertEqual(double(at: 0x44, in: data), 0.5, accuracy: 1e-9, "yRatio")
    // The second (duplicated) payload is adjusted: field1 = 1, field2 = 2 at 0xC0/0xC4.
    XCTAssertEqual(uint32(at: 0xC0, in: data), 1, "second payload touch.field1")
    XCTAssertEqual(uint32(at: 0xC4, in: data), 2, "second payload touch.field2")
  }

  func testTouchRatioMath() throws {
    let indigo = try makeIndigo()
    // 400x800 px @3x, point (100,100) -> ratio (0.75, 0.375).
    let data = indigo.touchScreenSize(CGSize(width: 400, height: 800), screenScale: 3, direction: .down, x: 100, y: 100)
    XCTAssertEqual(double(at: 0x3c, in: data), 0.75, accuracy: 1e-9, "xRatio = x*scale/width")
    XCTAssertEqual(double(at: 0x44, in: data), 0.375, accuracy: 1e-9, "yRatio = y*scale/height")
  }

  // MARK: - Two-finger touch

  func testTwoFingerPatchedRatios() throws {
    let indigo = try makeIndigo()
    // 200x400 px @2x. finger1 (50,100) -> (0.5,0.5); finger2 (100,200) -> (1.0,1.0).
    let data = indigo.twoFingerTouchScreenSize(
      CGSize(width: 200, height: 400),
      screenScale: 2,
      direction: .down,
      finger1: CGPoint(x: 50, y: 100),
      finger2: CGPoint(x: 100, y: 200))

    // Finger 1 ratio at 0x3C/0x44.
    XCTAssertEqual(double(at: 0x3C, in: data), 0.5, accuracy: 1e-9, "finger1 xRatio")
    XCTAssertEqual(double(at: 0x44, in: data), 0.5, accuracy: 1e-9, "finger1 yRatio")
    // Digitizer summary mirrors finger 1 at 0xDC/0xE4.
    XCTAssertEqual(double(at: 0xDC, in: data), 0.5, accuracy: 1e-9, "digitizer xRatio")
    XCTAssertEqual(double(at: 0xE4, in: data), 0.5, accuracy: 1e-9, "digitizer yRatio")
    // Finger 2 ratio at 0x17C/0x184.
    XCTAssertEqual(double(at: 0x17C, in: data), 1.0, accuracy: 1e-9, "finger2 xRatio")
    XCTAssertEqual(double(at: 0x184, in: data), 1.0, accuracy: 1e-9, "finger2 yRatio")
  }

  // MARK: - Button

  func testButtonEventSources() throws {
    let indigo = try makeIndigo()
    let expected: [(FBSimulatorHIDButton, UInt32)] = [
      (.applePay, 0x1f4),
      (.homeButton, 0x0),
      (.lock, 0x1),
      (.sideButton, 0xbb8),
      (.siri, 0x400002),
    ]
    for (button, source) in expected {
      let data = try XCTUnwrap(indigo.button(with: .down, button: button))
      // IndigoButton.eventSource at 0x30.
      XCTAssertEqual(uint32(at: 0x30, in: data), source, "eventSource for button rawValue \(button.rawValue)")
    }
  }

  func testConsumerOnlyButtonHasNoIndigoSource() {
    // `play_pause` is a Consumer-page button the legacy Indigo path cannot express, so it produces no
    // button message (the DTUHID transport delivers it instead).
    let indigo = try? makeIndigo()
    XCTAssertNil(indigo?.button(with: .down, button: .playPause))
  }

  func testButtonDirectionAndTarget() throws {
    let indigo = try makeIndigo()
    let down = try XCTUnwrap(indigo.button(with: .down, button: .homeButton))
    let up = try XCTUnwrap(indigo.button(with: .up, button: .homeButton))
    // IndigoButton.eventType at 0x34 == direction (down=1, up=2).
    XCTAssertEqual(uint32(at: 0x34, in: down), 1, "down eventType")
    XCTAssertEqual(uint32(at: 0x34, in: up), 2, "up eventType")
    // IndigoButton.eventTarget at 0x38 == ButtonEventTargetHardware (0x33).
    XCTAssertEqual(uint32(at: 0x38, in: down), 0x33, "eventTarget should be hardware")
  }

  // MARK: - Keyboard

  func testKeyboardPayloadIsKeyDependent() throws {
    let indigo = try makeIndigo()
    let a1 = indigo.keyboard(with: .down, keyCode: 0x04)
    let a2 = indigo.keyboard(with: .down, keyCode: 0x04)
    let b = indigo.keyboard(with: .down, keyCode: 0x05)
    // eventType byte at 0x1c == IndigoEventTypeButton (1) for the button/keyboard family.
    XCTAssertEqual(uint8(at: 0x1c, in: a1), 1, "keyboard eventType should be 1")
    // Apart from the per-call timestamp, the same keycode/direction is deterministic...
    XCTAssertEqual(zeroingTimestamp(a1), zeroingTimestamp(a2), "Same keycode/direction is stable apart from timestamp")
    // ...and a different keycode changes the payload (the keycode flows through).
    XCTAssertNotEqual(zeroingTimestamp(a1), zeroingTimestamp(b), "Distinct keycodes produce distinct payloads")
  }

  // MARK: - Trackpad (tvOS)

  // Pins the digitizer phase fields the tvOS trackpad sets on the two-IndigoPayload message: the
  // primary contact's IndigoTouch.eventMask (0x38) / range (0x64) / touch (0x68), and the second
  // payload's copies at 0xd8 / 0x104 / 0x108. The second payload sits at the wire offset 0xC0 (not
  // Swift's under-counted MemoryLayout<IndigoMessage>.size), so this also guards that offset.
  func testTrackpadPhaseFields() throws {
    let indigo = try makeIndigo()
    let point = CGPoint(x: 0.5, y: 0.5)

    // began: eventMask = Range|Touch|Identity (0x23); second-payload eventMask = 3.
    let began = try indigo.trackpad(point: point, phase: .began)
    XCTAssertEqual(uint32(at: 0x38, in: began), 0x23, "began eventMask")
    XCTAssertEqual(uint32(at: 0xd8, in: began), 3, "began second-payload eventMask")

    // changed: builder default — Position mask (0x04), no patches.
    let changed = try indigo.trackpad(point: point, phase: .changed)
    XCTAssertEqual(uint32(at: 0x38, in: changed), 0x04, "changed EventMask (builder default Position)")

    // ended: eventMask = Range|Identity (0x21), range/touch cleared on both payloads.
    let ended = try indigo.trackpad(point: point, phase: .ended)
    XCTAssertEqual(uint32(at: 0x38, in: ended), 0x21, "ended eventMask")
    XCTAssertEqual(uint32(at: 0x64, in: ended), 0, "ended range up")
    XCTAssertEqual(uint32(at: 0x68, in: ended), 0, "ended touch up")
    XCTAssertEqual(uint32(at: 0xd8, in: ended), 1, "ended second-payload eventMask")
    XCTAssertEqual(uint32(at: 0x104, in: ended), 0, "ended second-payload Range up")
    XCTAssertEqual(uint32(at: 0x108, in: ended), 0, "ended second-payload Touch up")
  }
}
