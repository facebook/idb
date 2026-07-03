/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Darwin
@preconcurrency import FBControlCore
import Foundation
@_implementationOnly import SimulatorApp

/// Translates FBSimulatorHID events into Indigo structs.
public final class FBSimulatorIndigoHID {

  // The SimulatorKit `IndigoHIDMessageFor*` functions, resolved at runtime via dlsym.
  private typealias MessageForButtonFn = @convention(c) (Int32, Int32, Int32) -> UnsafeMutablePointer<IndigoMessage>
  private typealias MessageForKeyboardArbitraryFn = @convention(c) (Int32, Int32) -> UnsafeMutablePointer<IndigoMessage>
  private typealias MessageForMouseNSEventFn =
    @convention(c) (
      UnsafeMutablePointer<CGPoint>?, UnsafeMutablePointer<CGPoint>?, Int32, Int32, ObjCBool
    ) -> UnsafeMutablePointer<IndigoMessage>
  // The SimulatorKit tvOS-trackpad builder: builds a touch-DOWN "changed" digitizer event for the
  // dedicated trackpad service (target 0x16). Callers set the returned message's digitizer phase
  // fields (see `trackpad(point:phase:)`) to express a began → changed → ended gesture.
  private typealias MessageForTrackpadMoveEventFn =
    @convention(c) (CGPoint, UInt32) -> UnsafeMutablePointer<IndigoMessage>

  private let messageForButton: MessageForButtonFn
  private let messageForKeyboardArbitrary: MessageForKeyboardArbitraryFn
  private let messageForMouseNSEvent: MessageForMouseNSEventFn
  private let messageForTrackpadMoveEvent: MessageForTrackpadMoveEventFn

  // MARK: Initializers

  /// The SimulatorKit implementation. Loads the xcode private frameworks and resolves the
  /// `IndigoHIDMessageFor*` symbols from the SimulatorKit dylib.
  public convenience init() throws {
    try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(nil)
    guard let handle = Bundle(identifier: "com.apple.SimulatorKit")?.dlopenExecutablePath() else {
      throw FBSimulatorHIDError.simulatorKitUnavailable
    }
    self.init(
      messageForButton: unsafeBitCast(FBGetSymbolFromHandle(handle, "IndigoHIDMessageForButton"), to: MessageForButtonFn.self),
      messageForKeyboardArbitrary: unsafeBitCast(
        FBGetSymbolFromHandle(handle, "IndigoHIDMessageForKeyboardArbitrary"), to: MessageForKeyboardArbitraryFn.self),
      messageForMouseNSEvent: unsafeBitCast(
        FBGetSymbolFromHandle(handle, "IndigoHIDMessageForMouseNSEvent"), to: MessageForMouseNSEventFn.self),
      messageForTrackpadMoveEvent: unsafeBitCast(
        FBGetSymbolFromHandle(handle, "IndigoHIDMessageForTrackpadMoveEvent"), to: MessageForTrackpadMoveEventFn.self))
  }

  private init(
    messageForButton: @escaping MessageForButtonFn,
    messageForKeyboardArbitrary: @escaping MessageForKeyboardArbitraryFn,
    messageForMouseNSEvent: @escaping MessageForMouseNSEventFn,
    messageForTrackpadMoveEvent: @escaping MessageForTrackpadMoveEventFn
  ) {
    self.messageForButton = messageForButton
    self.messageForKeyboardArbitrary = messageForKeyboardArbitrary
    self.messageForMouseNSEvent = messageForMouseNSEvent
    self.messageForTrackpadMoveEvent = messageForTrackpadMoveEvent
  }

  // MARK: Public

  /// A keyboard event. The keycodes are 'Hardware Independent' as described in `<HIToolbox/Events.h>`.
  public func keyboard(with direction: FBSimulatorHIDDirection, keyCode: UInt32) -> Data {
    let message = messageForKeyboardArbitrary(Int32(bitPattern: keyCode), direction.rawValue)
    return FBSimulatorIndigoHID.data(fromMallocedMessage: message)
  }

  /// A button event, or `nil` when the button has no legacy Indigo source (a Consumer-page button
  /// such as `play_pause` that only the DTUHID transport can deliver).
  public func button(with direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) -> Data? {
    guard let source = button.indigoEventSource else {
      return nil
    }
    let message = messageForButton(source, direction.rawValue, Int32(ButtonEventTargetHardware))
    return FBSimulatorIndigoHID.data(fromMallocedMessage: message)
  }

  /// The dedicated tvOS trackpad HID service target (what Simulator.app's on-screen remote hard-codes;
  /// NOT the `screenID | 0x40000000` screen target, which binds to the main-screen digitizer and does
  /// not move tvOS focus).
  private static let trackpadTarget: UInt32 = 0x16

  /// Wire offset of the second `IndigoPayload` in a SimulatorKit-built message (Indigo.h: a single-payload
  /// allocation is 0xC0). NB: this is the *wire* offset — Swift's `MemoryLayout<IndigoMessage>.size`
  /// under-counts it (0xB0) because of the packed union, so it cannot be used to locate the payload.
  private static let secondPayloadWireOffset = 0xC0
  /// Wire stride between consecutive `IndigoPayload`s in a SimulatorKit-built message. The packed union
  /// makes this larger than `MemoryLayout<IndigoPayload>.size` (which is 0x90).
  private static let payloadWireStride = 0xA0
  /// Wire offset of the third `IndigoPayload` — the second finger in a multi-touch message.
  private static let thirdPayloadWireOffset = secondPayloadWireOffset + payloadWireStride

  /// A tvOS Siri Remote trackpad move. Builds `IndigoHIDMessageForTrackpadMoveEvent(point, 0x16)` and
  /// sets its digitizer phase fields so the focus engine reads a began → changed → ended gesture
  /// rather than a stream of stationary positions (a bare position stream is accepted but does not
  /// move focus). `point` is absolute-normalized (0..1, top-left origin).
  ///
  /// The builder emits a *two*-`IndigoPayload` message (like the multi-touch builder): the primary
  /// contact in `message.payload`, a repeated contact in the `IndigoPayload` immediately after the
  /// message (at `MemoryLayout<IndigoMessage>.size` — see `twoFingerTouchScreenSize`'s payload 2 at
  /// 0xC0). Both carry the digitizer state in `IndigoTouch.eventMask` (IOHIDDigitizerEventMask: Range
  /// 0x1 | Touch 0x2 | Position 0x4 | Identity 0x20), `range`, and `touch`; the builder defaults to a
  /// Position/touch-down "changed" contact.
  public func trackpad(point: CGPoint, phase: FBSimulatorTrackpadPhase) throws -> Data {
    let message = messageForTrackpadMoveEvent(point, FBSimulatorIndigoHID.trackpadTarget)
    let secondary = FBSimulatorIndigoHID.payload(at: FBSimulatorIndigoHID.secondPayloadWireOffset, of: message)
    switch phase {
    case .began:
      message.pointee.payload.event.touch.eventMask = 0x23 // Range|Touch|Identity
      secondary.pointee.event.touch.eventMask = 3
    case .changed:
      break // builder default: Position mask, touch down
    case .ended:
      message.pointee.payload.event.touch.eventMask = 0x21 // Range|Identity, Touch cleared
      message.pointee.payload.event.touch.range = 0 // out of range
      message.pointee.payload.event.touch.touch = 0 // contact up
      secondary.pointee.event.touch.eventMask = 1
      secondary.pointee.event.touch.range = 0
      secondary.pointee.event.touch.touch = 0
    }
    return FBSimulatorIndigoHID.data(fromMallocedMessage: message)
  }

  /// A single-finger touch event. `x`/`y` are in points; `screenSize` is in pixels.
  public func touchScreenSize(
    _ screenSize: CGSize, screenScale: Float, direction: FBSimulatorHIDDirection, x: Double, y: Double
  ) -> Data {
    // Convert Screen Offset to Ratio for Indigo.
    let point = FBSimulatorIndigoHID.screenRatio(from: CGPoint(x: x, y: y), screenSize: screenSize, screenScale: screenScale)
    return touchMessage(point: point, direction: direction)
  }

  /// A two-finger touch event for multi-touch gestures (pinch, rotate, etc.).
  public func twoFingerTouchScreenSize(
    _ screenSize: CGSize, screenScale: Float, direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint
  ) -> Data {
    var ratio1 = FBSimulatorIndigoHID.screenRatio(from: finger1, screenSize: screenSize, screenScale: screenScale)
    var ratio2 = FBSimulatorIndigoHID.screenRatio(from: finger2, screenSize: screenSize, screenScale: screenScale)

    // Passing a non-NULL second point makes IndigoHIDMessageForMouseNSEvent produce a 3-payload message
    // with eventType=0x03 (multi-touch) instead of 0x02 (single-touch).
    let message = messageForMouseNSEvent(&ratio1, &ratio2, 0x32, direction.indigoEventType, ObjCBool(false))

    // The builder does not store our coordinates directly — patch each contact's xRatio/yRatio. Finger 1
    // is the primary contact, the digitizer summary (payload 2) mirrors it, and finger 2 is payload 3.
    message.pointee.payload.event.touch.xRatio = ratio1.x
    message.pointee.payload.event.touch.yRatio = ratio1.y
    let digitizer = FBSimulatorIndigoHID.payload(at: FBSimulatorIndigoHID.secondPayloadWireOffset, of: message)
    digitizer.pointee.event.touch.xRatio = ratio1.x
    digitizer.pointee.event.touch.yRatio = ratio1.y
    let finger2Payload = FBSimulatorIndigoHID.payload(at: FBSimulatorIndigoHID.thirdPayloadWireOffset, of: message)
    finger2Payload.pointee.event.touch.xRatio = ratio2.x
    finger2Payload.pointee.event.touch.yRatio = ratio2.y

    return FBSimulatorIndigoHID.data(fromMallocedMessage: message)
  }

  // MARK: Event Generation

  private func touchMessage(point: CGPoint, direction: FBSimulatorHIDDirection) -> Data {
    var point = point
    let source = messageForMouseNSEvent(&point, nil, 0x32, direction.indigoEventType, ObjCBool(false))
    let sourceBytes = UnsafeMutableRawPointer(source)
    // Patch xRatio (0x3C) / yRatio (0x44) into the source IndigoTouch.
    FBSimulatorIndigoHID.write(point.x, at: 0x3C, into: sourceBytes)
    FBSimulatorIndigoHID.write(point.y, at: 0x44, into: sourceBytes)

    // Build a fresh touch message (320 / 0x140 bytes) and copy the Digitizer payload in.
    let messageSize = MemoryLayout<IndigoMessage>.size + MemoryLayout<IndigoPayload>.size
    let stride = MemoryLayout<IndigoPayload>.size // 0x90
    guard let destination = calloc(1, messageSize) else {
      fatalError("Failed to allocate \(messageSize) bytes for an Indigo touch message")
    }
    let message = destination.assumingMemoryBound(to: IndigoMessage.self)
    message.pointee.innerSize = UInt32(MemoryLayout<IndigoPayload>.size)
    message.pointee.eventType = UInt8(IndigoEventTypeTouch)
    message.pointee.payload.field1 = 0x0000_000B
    message.pointee.payload.timestamp = mach_absolute_time()

    // Copy in the Digitizer (IndigoTouch) payload from the source, at event offset 0x30.
    memcpy(destination.advanced(by: 0x30), sourceBytes.advanced(by: 0x30), MemoryLayout<IndigoTouch>.size)
    free(source)

    // Duplicate the first IndigoPayload (at 0x20) into the second slot, and mark it
    // (second touch.field1 = 1, field2 = 2 — the bits at 0x30 + stride).
    memcpy(destination.advanced(by: 0x20 + stride), destination.advanced(by: 0x20), stride)
    FBSimulatorIndigoHID.write(UInt32(1), at: 0x30 + stride, into: destination)
    FBSimulatorIndigoHID.write(UInt32(2), at: 0x34 + stride, into: destination)

    return Data(bytesNoCopy: destination, count: messageSize, deallocator: .free)
  }

  // MARK: Helpers

  /// Wraps a `malloc`'d `IndigoMessage` as `Data` that frees the buffer when deallocated.
  private static func data(fromMallocedMessage message: UnsafeMutablePointer<IndigoMessage>) -> Data {
    let raw = UnsafeMutableRawPointer(message)
    return Data(bytesNoCopy: raw, count: malloc_size(raw), deallocator: .free)
  }

  /// A typed view of the `IndigoPayload` at a wire offset the Swift `IndigoMessage.payload` field cannot
  /// address — SimulatorKit lays the second and third payloads at `payloadWireStride`, which the packed
  /// union under-counts. Used for the digitizer/second-finger contacts in multi-payload messages.
  private static func payload(
    at wireOffset: Int, of message: UnsafeMutablePointer<IndigoMessage>
  ) -> UnsafeMutablePointer<IndigoPayload> {
    UnsafeMutableRawPointer(message).advanced(by: wireOffset).assumingMemoryBound(to: IndigoPayload.self)
  }

  static func screenRatio(from point: CGPoint, screenSize: CGSize, screenScale: Float) -> CGPoint {
    CGPoint(
      x: (point.x * CGFloat(screenScale)) / screenSize.width,
      y: (point.y * CGFloat(screenScale)) / screenSize.height)
  }

  private static func write(_ value: Double, at offset: Int, into base: UnsafeMutableRawPointer) {
    var value = value
    memcpy(base.advanced(by: offset), &value, MemoryLayout<Double>.size)
  }

  private static func write(_ value: UInt32, at offset: Int, into base: UnsafeMutableRawPointer) {
    var value = value
    memcpy(base.advanced(by: offset), &value, MemoryLayout<UInt32>.size)
  }
}

// MARK: - Indigo wire-format mappings

private extension FBSimulatorHIDButton {
  /// The Indigo `eventSource` value for this button, or `nil` when the legacy Indigo path has no
  /// source for it — a Consumer-page button such as `play_pause` that only the DTUHID transport
  /// can deliver (the mirror image of `apple_pay`, which has an Indigo source but no DTUHID usage).
  var indigoEventSource: Int32? {
    switch self {
    case .applePay:
      return Int32(ButtonEventSourceApplePay)
    case .homeButton:
      return Int32(ButtonEventSourceHomeButton)
    case .lock:
      return Int32(ButtonEventSourceLock)
    case .sideButton:
      return Int32(ButtonEventSourceSideButton)
    case .siri:
      return Int32(ButtonEventSourceSiri)
    case .playPause:
      return nil
    }
  }
}

private extension FBSimulatorHIDDirection {
  /// The Indigo `eventType` value for this direction.
  var indigoEventType: Int32 {
    switch self {
    case .down:
      return Int32(ButtonEventTypeDown)
    case .up:
      return Int32(ButtonEventTypeUp)
    }
  }
}
