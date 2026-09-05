/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
// Matches the existing XCTest-based FBSimulatorControl unit suite (FBSimulatorPurpleHIDTests et al.).
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

/// Counts `loadPrivateFrameworks` calls without dlopening anything, so a test can observe whether the
/// code under test asks for its frameworks. The process-global load state cannot answer that: the
/// other suites in this test bundle share the process and have already loaded them.
private final class RecordingFrameworkLoader: FBControlCoreFrameworkLoader {

  private(set) var loadCount = 0

  override func loadPrivateFrameworks(_ logger: FBControlCoreLogger?) throws {
    loadCount += 1
  }
}

/// Byte-level coverage of the Indigo payloads produced by `FBSimulatorIndigoHID`, plus the
/// resolution of the runtime-only client class that carries them.
/// Offsets are taken from `Source/PrivateHeaders/SimulatorApp/Indigo.h`.
final class FBSimulatorIndigoHIDTests: XCTestCase {

  override func setUpWithError() throws {
    try super.setUpWithError()
    // FBSimulatorIndigoHID() dlopens SimulatorKit. Pre-load the private
    // frameworks with the default logger (CoreSimulator, then SimulatorKit) so that the
    // builder's internal load is a no-op — its nil-logger load path would otherwise crash
    // when it is the first loader call in a bare unit-test process. The loads are memoized,
    // so per-test invocation is a no-op after the first.
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(FBControlCoreGlobalConfiguration.defaultLogger)
    try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(FBControlCoreGlobalConfiguration.defaultLogger)
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
    XCTAssertEqual(uint32(at: 0x20, in: data), 0x0b, "payload.eventKind should be 0x0b")
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

  // The digitizer contact state encodes direction: `.down` sets range/touch (contact down), `.up`
  // clears them (contact up). The eventKind (0x20) and touch-down eventMask (0x38) are the same for
  // both directions.
  func testTouchContactAndDirection() throws {
    let indigo = try makeIndigo()
    let size = CGSize(width: 200, height: 400)
    let down = indigo.touchScreenSize(size, screenScale: 2, direction: .down, x: 50, y: 100)
    let up = indigo.touchScreenSize(size, screenScale: 2, direction: .up, x: 50, y: 100)

    XCTAssertEqual(uint32(at: 0x20, in: down), 0x0b, "eventKind")
    XCTAssertEqual(uint32(at: 0x38, in: down), 0x03, "touch-down eventMask")
    // down: contact present (range 0x64 = 1, touch 0x68 = 1).
    XCTAssertEqual(uint32(at: 0x64, in: down), 1, "down range")
    XCTAssertEqual(uint32(at: 0x68, in: down), 1, "down touch")
    // up: contact released (range/touch cleared).
    XCTAssertEqual(uint32(at: 0x64, in: up), 0, "up range")
    XCTAssertEqual(uint32(at: 0x68, in: up), 0, "up touch")
    // The second (duplicated) payload begins at the wire offset 0xb0 with its own eventKind.
    XCTAssertEqual(uint32(at: 0xb0, in: down), 0x0b, "second payload eventKind at 0xb0")
  }

  // An edge-originating contact carries the IOHIDDigitizerEventMask swipe bit for the direction the
  // gesture travels, OR'd into the usual Range|Touch (0x3). The guest reads the system edge gestures
  // off these bits, so they are the whole difference between a swipe and a home-indicator gesture.
  func testEdgeTouchSetsTheSwipeEventMaskBits() throws {
    let indigo = try makeIndigo()
    let size = CGSize(width: 200, height: 400)
    let expected: [(FBSimulatorHIDEdge, UInt32)] = [
      (.none, 0x0000_0003),
      (.top, 0x0204_0003), // SwipeDown — a swipe from the top travels down
      (.left, 0x0804_0003), // SwipeRight
      (.bottom, 0x0104_0003), // SwipeUp
      (.right, 0x0404_0003), // SwipeLeft
    ]
    for (edge, mask) in expected {
      let data = indigo.touchScreenSize(size, screenScale: 2, direction: .down, x: 50, y: 100, edge: edge)
      XCTAssertEqual(uint32(at: 0x38, in: data), mask, "eventMask for the \(edge.name) edge")
    }
  }

  // The edge changes only the eventMask — the coordinates and contact state are untouched, so an edge
  // swipe is an ordinary swipe as far as everything downstream of the flag is concerned.
  func testEdgeTouchLeavesTheContactOtherwiseUnchanged() throws {
    let indigo = try makeIndigo()
    let size = CGSize(width: 200, height: 400)
    let plain = indigo.touchScreenSize(size, screenScale: 2, direction: .down, x: 50, y: 100)
    let edged = indigo.touchScreenSize(size, screenScale: 2, direction: .down, x: 50, y: 100, edge: .bottom)

    XCTAssertEqual(plain.count, edged.count, "message size")
    XCTAssertEqual(double(at: 0x3c, in: edged), double(at: 0x3c, in: plain), accuracy: 1e-9, "xRatio")
    XCTAssertEqual(double(at: 0x44, in: edged), double(at: 0x44, in: plain), accuracy: 1e-9, "yRatio")
    XCTAssertEqual(uint32(at: 0x64, in: edged), uint32(at: 0x64, in: plain), "range")
    XCTAssertEqual(uint32(at: 0x68, in: edged), uint32(at: 0x68, in: plain), "touch")
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

    XCTAssertEqual(double(at: 0x3C, in: data), 0.5, accuracy: 1e-9, "finger1 xRatio")
    XCTAssertEqual(double(at: 0x44, in: data), 0.5, accuracy: 1e-9, "finger1 yRatio")
    // Digitizer summary mirrors finger 1 at 0xDC/0xE4.
    XCTAssertEqual(double(at: 0xDC, in: data), 0.5, accuracy: 1e-9, "digitizer xRatio")
    XCTAssertEqual(double(at: 0xE4, in: data), 0.5, accuracy: 1e-9, "digitizer yRatio")
    XCTAssertEqual(double(at: 0x17C, in: data), 1.0, accuracy: 1e-9, "finger2 xRatio")
    XCTAssertEqual(double(at: 0x184, in: data), 1.0, accuracy: 1e-9, "finger2 yRatio")
  }

  // The multi-touch message identity: eventType 0x03 (vs single-touch 0x02), innerSize 0xa0, and the
  // three-payload size 0x200. Direction flips the primary digitizer contact like single-touch.
  func testTwoFingerMessageIdentity() throws {
    let indigo = try makeIndigo()
    let size = CGSize(width: 200, height: 400)
    let finger1 = CGPoint(x: 50, y: 100)
    let finger2 = CGPoint(x: 100, y: 200)
    let down = indigo.twoFingerTouchScreenSize(size, screenScale: 2, direction: .down, finger1: finger1, finger2: finger2)
    let up = indigo.twoFingerTouchScreenSize(size, screenScale: 2, direction: .up, finger1: finger1, finger2: finger2)

    XCTAssertEqual(down.count, 0x200, "two-finger message size")
    XCTAssertEqual(uint32(at: 0x18, in: down), 0xa0, "innerSize")
    XCTAssertEqual(uint8(at: 0x1c, in: down), 3, "eventType should be multi-touch")
    XCTAssertEqual(uint32(at: 0x20, in: down), 0x0b, "eventKind")
    XCTAssertEqual(uint32(at: 0x64, in: down), 1, "down range")
    XCTAssertEqual(uint32(at: 0x64, in: up), 0, "up range")
    XCTAssertEqual(uint32(at: 0x68, in: up), 0, "up touch")
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
      let data = indigo.button(with: .down, button: button)
      // IndigoButton.eventSource at 0x30.
      XCTAssertEqual(uint32(at: 0x30, in: data), source, "eventSource for button rawValue \(button.rawValue)")
    }
  }

  // Driven off `allCases` so a button added later has to land on one side or the other rather than
  // silently joining the unsupported set.
  func testEveryButtonHasALegacyIndigoMessage() throws {
    let indigo = try makeIndigo()
    let unsupported = FBSimulatorHIDButton.allCases
      .filter { indigo.button(with: .down, button: $0).isEmpty }
      .map(\.name)
    XCTAssertEqual(unsupported, [])
  }

  // `play_pause` is the button that had no dedicated `ButtonEventSource`, so it is the one this
  // routes down the arbitrary-HID path: same hardware target and direction as a sourced button, but
  // the source is `ButtonEventSourceHIDArbitrary` and the Consumer usage rides in `keyCode`.
  func testConsumerPageButtonUsesTheArbitraryHIDSource() throws {
    let indigo = try makeIndigo()
    let data = indigo.button(with: .down, button: .playPause)

    XCTAssertEqual(uint32(at: 0x30, in: data), 0x2711, "eventSource should be arbitrary HID")
    XCTAssertEqual(uint32(at: 0x38, in: data), 0x33, "eventTarget (hardware)")
    XCTAssertEqual(uint32(at: 0x3c, in: data), 0xCD, "Consumer Play/Pause usage")
    XCTAssertEqual(uint32(at: 0x44, in: data), 0x0C, "Consumer usage page")
  }

  // The whole button envelope, not just its event source: the 0xc0-byte single-payload allocation, the
  // innerSize, the button-family eventType byte and eventKind, and every IndigoButton field.
  func testButtonMessageEnvelope() throws {
    let indigo = try makeIndigo()
    let data = indigo.button(with: .down, button: .homeButton)

    XCTAssertEqual(data.count, 0xc0, "single-payload button message size")
    XCTAssertEqual(uint32(at: 0x18, in: data), 0xa0, "innerSize")
    XCTAssertEqual(uint8(at: 0x1c, in: data), 1, "eventType should be the button family")
    XCTAssertEqual(uint32(at: 0x20, in: data), 2, "payload.eventKind")
    XCTAssertEqual(uint32(at: 0x30, in: data), 0x0, "eventSource (home)")
    XCTAssertEqual(uint32(at: 0x34, in: data), 1, "eventType (down)")
    XCTAssertEqual(uint32(at: 0x38, in: data), 0x33, "eventTarget (hardware)")
    XCTAssertEqual(uint32(at: 0x3c, in: data), 0, "the sourced-button builder leaves keyCode unset")
    XCTAssertEqual(uint32(at: 0x40, in: data), 0, "field5")
  }

  func testButtonDirectionAndTarget() throws {
    let indigo = try makeIndigo()
    let down = indigo.button(with: .down, button: .homeButton)
    let up = indigo.button(with: .up, button: .homeButton)
    // IndigoButton.eventType at 0x34 == direction (down=1, up=2).
    XCTAssertEqual(uint32(at: 0x34, in: down), 1, "down eventType")
    XCTAssertEqual(uint32(at: 0x34, in: up), 2, "up eventType")
    // IndigoButton.eventTarget at 0x38 == ButtonEventTargetHardware (0x33).
    XCTAssertEqual(uint32(at: 0x38, in: down), 0x33, "eventTarget should be hardware")
  }

  // MARK: - Arbitrary HID usage

  // The arbitrary-HID builder names a usage rather than a button: the source is
  // ButtonEventSourceHIDArbitrary (0x2711, one above the keyboard source), the usage lands in
  // IndigoButton.keyCode (0x3c) and its page in IndigoButton.usagePage (0x44), and the target is the
  // same hardware-button service a sourced button uses.
  func testArbitraryHIDUsageFields() throws {
    let indigo = try makeIndigo()
    let down = indigo.hidArbitrary(page: 0x0C, usage: 0xCD, direction: .down)
    let up = indigo.hidArbitrary(page: 0x0C, usage: 0xCD, direction: .up)

    XCTAssertEqual(uint32(at: 0x30, in: down), 0x2711, "eventSource should be arbitrary HID")
    XCTAssertEqual(uint32(at: 0x34, in: down), 1, "down eventType")
    XCTAssertEqual(uint32(at: 0x34, in: up), 2, "up eventType")
    XCTAssertEqual(uint32(at: 0x38, in: down), 0x33, "eventTarget (hardware)")
    XCTAssertEqual(uint32(at: 0x3c, in: down), 0xCD, "usage lands in keyCode")
    XCTAssertEqual(uint32(at: 0x44, in: down), 0x0C, "page lands in usagePage")
  }

  // The page and usage are carried independently, so the builder is not hard-wired to one page.
  func testArbitraryHIDUsageCarriesAnyPageAndUsage() throws {
    let indigo = try makeIndigo()
    let data = indigo.hidArbitrary(page: 0x07, usage: 0x4F, direction: .down)
    XCTAssertEqual(uint32(at: 0x3c, in: data), 0x4F, "usage")
    XCTAssertEqual(uint32(at: 0x44, in: data), 0x07, "page")
  }

  // The arbitrary-HID message is the same envelope as a sourced button, so the two are
  // interchangeable to everything downstream of the builder.
  func testArbitraryHIDUsageSharesTheSourcedButtonEnvelope() throws {
    let indigo = try makeIndigo()
    let arbitrary = indigo.hidArbitrary(page: 0x0C, usage: 0xCD, direction: .down)
    let sourced = indigo.button(with: .down, button: .homeButton)

    XCTAssertEqual(arbitrary.count, sourced.count, "message size")
    XCTAssertEqual(uint32(at: 0x18, in: arbitrary), uint32(at: 0x18, in: sourced), "innerSize")
    XCTAssertEqual(uint8(at: 0x1c, in: arbitrary), uint8(at: 0x1c, in: sourced), "eventType byte")
    XCTAssertEqual(uint32(at: 0x20, in: arbitrary), uint32(at: 0x20, in: sourced), "payload.eventKind")
  }

  // MARK: - Keyboard

  func testKeyboardPayloadIsKeyDependent() throws {
    let indigo = try makeIndigo()
    let a1 = indigo.keyboard(with: .down, keyCode: 0x04)
    let a2 = indigo.keyboard(with: .down, keyCode: 0x04)
    let b = indigo.keyboard(with: .down, keyCode: 0x05)
    // eventType byte at 0x1c == IndigoEventTypeButton (1) for the button/keyboard family.
    XCTAssertEqual(uint8(at: 0x1c, in: a1), 1, "keyboard eventType should be 1")
    XCTAssertEqual(zeroingTimestamp(a1), zeroingTimestamp(a2), "Same keycode/direction is stable apart from timestamp")
    XCTAssertNotEqual(zeroingTimestamp(a1), zeroingTimestamp(b), "Distinct keycodes produce distinct payloads")
  }

  // The keyboard message routes to the keyboard service: eventSource 0x2710, eventTarget 0x64, the
  // keyCode flows to 0x3c, and direction sets eventType (down=1, up=2).
  func testKeyboardDirectionAndFields() throws {
    let indigo = try makeIndigo()
    let down = indigo.keyboard(with: .down, keyCode: 0x04)
    let up = indigo.keyboard(with: .up, keyCode: 0x04)

    XCTAssertEqual(uint32(at: 0x30, in: down), 0x2710, "eventSource should be keyboard")
    XCTAssertEqual(uint32(at: 0x34, in: down), 1, "down eventType")
    XCTAssertEqual(uint32(at: 0x34, in: up), 2, "up eventType")
    XCTAssertEqual(uint32(at: 0x38, in: down), 0x64, "eventTarget should be keyboard")
    XCTAssertEqual(uint32(at: 0x3c, in: down), 0x04, "keyCode flows to 0x3c")
  }

  // MARK: - Client class resolution

  // `SimDeviceLegacyHIDClient` is vended by SimulatorKit, which only the `xcodeFrameworks` loader
  // dlopens — `FBSimulatorControl` on its own loads just the essential set (CoreSimulator).
  func testResolvingTheClientClassLoadsTheXcodeFrameworks() {
    let loader = RecordingFrameworkLoader(name: "SimulatorKit", frameworks: [])
    // `try?`: the class itself has relocated across Xcodes, so whether the lookup succeeds on the
    // host running this test is beside the point — what is pinned is the loading, not the result.
    _ = try? FBSimulatorIndigoHIDClient.resolveClientClass(loader: loader)
    XCTAssertEqual(loader.loadCount, 1)
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

  // The trackpad message identity (a single-touch 0x02 envelope, innerSize 0xa0, two-payload size
  // 0x180) and that the input point reaches the primary digitizer coordinates at xRatio/yRatio.
  func testTrackpadMessageIdentity() throws {
    let indigo = try makeIndigo()
    let data = try indigo.trackpad(point: CGPoint(x: 0.5, y: 0.5), phase: .changed)
    XCTAssertEqual(uint8(at: 0x1c, in: data), 2, "trackpad eventType should be touch")
    XCTAssertEqual(uint32(at: 0x18, in: data), 0xa0, "trackpad innerSize")
    XCTAssertEqual(data.count, 0x180, "trackpad message size")
    XCTAssertEqual(double(at: 0x3c, in: data), 0.5, accuracy: 1e-9, "trackpad xRatio")
    XCTAssertEqual(double(at: 0x44, in: data), 0.5, accuracy: 1e-9, "trackpad yRatio")
  }
}
