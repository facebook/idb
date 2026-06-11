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

/// The direction of a HID event.
@objc public enum FBSimulatorHIDDirection: Int32, Sendable {
  case down = 1
  case up = 2
}

/// A hardware button press.
@objc public enum FBSimulatorHIDButton: Int32, Sendable {
  case applePay = 1
  case homeButton = 2
  case lock = 3
  case sideButton = 4
  case siri = 5
}

/// Device orientation. Values match UIDeviceOrientation (1-4, excluding faceUp/faceDown).
@objc public enum FBSimulatorHIDDeviceOrientation: Int32, Sendable {
  case portrait = 1
  case portraitUpsideDown = 2
  case landscapeRight = 3
  case landscapeLeft = 4
}

/// Translates FBSimulatorHID events into Indigo structs.
@objc public final class FBSimulatorIndigoHID: NSObject {

  // The SimulatorKit `IndigoHIDMessageFor*` functions, resolved at runtime via dlsym.
  private typealias MessageForButtonFn = @convention(c) (Int32, Int32, Int32) -> UnsafeMutablePointer<IndigoMessage>
  private typealias MessageForKeyboardArbitraryFn = @convention(c) (Int32, Int32) -> UnsafeMutablePointer<IndigoMessage>
  private typealias MessageForMouseNSEventFn =
    @convention(c) (
      UnsafeMutablePointer<CGPoint>?, UnsafeMutablePointer<CGPoint>?, Int32, Int32, ObjCBool
    ) -> UnsafeMutablePointer<IndigoMessage>

  private let messageForButton: MessageForButtonFn
  private let messageForKeyboardArbitrary: MessageForKeyboardArbitraryFn
  private let messageForMouseNSEvent: MessageForMouseNSEventFn

  // MARK: Initializers

  /// The SimulatorKit implementation. Loads the xcode private frameworks and resolves the
  /// `IndigoHIDMessageFor*` symbols from the SimulatorKit dylib.
  public static func simulatorKitHID() throws -> FBSimulatorIndigoHID {
    try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(nil)
    guard let handle = Bundle(identifier: "com.apple.SimulatorKit")?.dlopenExecutablePath() else {
      throw FBSimulatorHIDError.simulatorKitUnavailable
    }
    return FBSimulatorIndigoHID(
      messageForButton: unsafeBitCast(FBGetSymbolFromHandle(handle, "IndigoHIDMessageForButton"), to: MessageForButtonFn.self),
      messageForKeyboardArbitrary: unsafeBitCast(
        FBGetSymbolFromHandle(handle, "IndigoHIDMessageForKeyboardArbitrary"), to: MessageForKeyboardArbitraryFn.self),
      messageForMouseNSEvent: unsafeBitCast(
        FBGetSymbolFromHandle(handle, "IndigoHIDMessageForMouseNSEvent"), to: MessageForMouseNSEventFn.self))
  }

  private init(
    messageForButton: @escaping MessageForButtonFn,
    messageForKeyboardArbitrary: @escaping MessageForKeyboardArbitraryFn,
    messageForMouseNSEvent: @escaping MessageForMouseNSEventFn
  ) {
    self.messageForButton = messageForButton
    self.messageForKeyboardArbitrary = messageForKeyboardArbitrary
    self.messageForMouseNSEvent = messageForMouseNSEvent
    super.init()
  }

  // MARK: Public

  /// A keyboard event. The keycodes are 'Hardware Independent' as described in `<HIToolbox/Events.h>`.
  @objc public func keyboard(with direction: FBSimulatorHIDDirection, keyCode: UInt32) -> Data {
    let message = messageForKeyboardArbitrary(Int32(bitPattern: keyCode), direction.rawValue)
    return FBSimulatorIndigoHID.data(fromMallocedMessage: message)
  }

  /// A button event.
  @objc public func button(with direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) -> Data {
    let message = messageForButton(button.indigoEventSource, direction.rawValue, Int32(ButtonEventTargetHardware))
    return FBSimulatorIndigoHID.data(fromMallocedMessage: message)
  }

  /// A single-finger touch event. `x`/`y` are in points; `screenSize` is in pixels.
  @objc public func touchScreenSize(
    _ screenSize: CGSize, screenScale: Float, direction: FBSimulatorHIDDirection, x: Double, y: Double
  ) -> Data {
    // Convert Screen Offset to Ratio for Indigo.
    let point = FBSimulatorIndigoHID.screenRatio(from: CGPoint(x: x, y: y), screenSize: screenSize, screenScale: screenScale)
    return touchMessage(point: point, direction: direction)
  }

  /// A two-finger touch event for multi-touch gestures (pinch, rotate, etc.).
  @objc public func twoFingerTouchScreenSize(
    _ screenSize: CGSize, screenScale: Float, direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint
  ) -> Data {
    var ratio1 = FBSimulatorIndigoHID.screenRatio(from: finger1, screenSize: screenSize, screenScale: screenScale)
    var ratio2 = FBSimulatorIndigoHID.screenRatio(from: finger2, screenSize: screenSize, screenScale: screenScale)

    // Passing a non-NULL point1 makes IndigoHIDMessageForMouseNSEvent produce a 3-payload message
    // with eventType=0x03 (multi-touch) instead of 0x02 (single-touch).
    let message = messageForMouseNSEvent(&ratio1, &ratio2, 0x32, direction.indigoEventType, ObjCBool(false))
    let messageSize = malloc_size(message)
    let bytes = UnsafeMutableRawPointer(message)

    // The function does not store our coordinates directly — patch them manually.
    // Byte offsets derived from Indigo.h struct layout (IndigoPayload stride = 0xA0):
    //   Payload 1 (finger 1) at 0x20:  xRatio at 0x3C, yRatio at 0x44
    //   Payload 2 (digitizer) at 0xC0: xRatio at 0xDC, yRatio at 0xE4
    //   Payload 3 (finger 2) at 0x160: xRatio at 0x17C, yRatio at 0x184
    FBSimulatorIndigoHID.write(ratio1.x, at: 0x3C, into: bytes)
    FBSimulatorIndigoHID.write(ratio1.y, at: 0x44, into: bytes)
    FBSimulatorIndigoHID.write(ratio1.x, at: 0xDC, into: bytes)
    FBSimulatorIndigoHID.write(ratio1.y, at: 0xE4, into: bytes)
    FBSimulatorIndigoHID.write(ratio2.x, at: 0x17C, into: bytes)
    FBSimulatorIndigoHID.write(ratio2.y, at: 0x184, into: bytes)

    return Data(bytesNoCopy: bytes, count: messageSize, deallocator: .free)
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

  private static func screenRatio(from point: CGPoint, screenSize: CGSize, screenScale: Float) -> CGPoint {
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
  /// The Indigo `eventSource` value for this button.
  var indigoEventSource: Int32 {
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
