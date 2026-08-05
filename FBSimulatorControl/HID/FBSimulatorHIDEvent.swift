/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

private let shakeDarwinNotification = "com.apple.UIKit.SimulatorShake"
private let inCallStatusBarNotification = "com.apple.iphonesimulator.toggleincallstatusbar"

// MARK: - FBSimulatorHIDEvent

/// A HID event that can be sent to a Simulator. A discriminated union of the primitive
/// payloads (touch, button, keyboard, two-finger touch, orientation, shake, lock, in-call
/// status bar, delay) plus a `composite` of ordered events.
public indirect enum FBSimulatorHIDEvent: Equatable, Hashable, Sendable {

  /// The per-sample step, in points, a swipe is broken into when the caller does not choose one.
  public static let defaultSwipeDelta: Double = 10.0

  case touch(direction: FBSimulatorHIDDirection, x: Double, y: Double)
  case button(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton)
  case keyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32)
  case twoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint)
  case trackpad(phase: FBSimulatorTrackpadPhase, point: FBSimulatorTrackpadPoint)
  case delay(TimeInterval)
  case deviceOrientation(FBSimulatorHIDDeviceOrientation)
  case shake
  case toggleInCallStatusBar
  case lockDevice
  case composite([FBSimulatorHIDEvent])

  /// For a `.composite` event, its ordered sub-events; otherwise `nil`.
  public var subEvents: [FBSimulatorHIDEvent]? {
    guard case let .composite(events) = self else {
      return nil
    }
    return events
  }

  /// Whether delivering this event writes to the HID transport, and so leaves something for the
  /// post-gesture drain to wait on.
  ///
  /// Not every case of this enum is a HID event. Orientation and lock go out as Purple mach messages,
  /// shake and the in-call status bar as Darwin notifications, and `.delay` writes nothing at all —
  /// none of them touch the transport, so there is nothing for `flush()` to drain afterwards. A
  /// `.composite` writes if any of its sub-events do.
  public var writesToTransport: Bool {
    switch self {
    case .touch, .button, .keyboard, .twoFingerTouch, .trackpad:
      return true
    case .deviceOrientation, .lockDevice, .shake, .toggleInCallStatusBar, .delay:
      return false
    case let .composite(events):
      return events.contains { $0.writesToTransport }
    }
  }
}

// MARK: - Dispatch

public extension FBSimulatorHIDEvent {

  /// Sends the event on the provided HID, completing when delivery is acknowledged.
  /// A `.composite` sends its sub-events in order; `.delay` suspends the task.
  func sendAsync(on hid: FBSimulatorHID) async throws {
    switch self {
    case let .touch(direction, x, y):
      try await hid.sendTouch(direction: direction, x: x, y: y)
    case let .button(direction, button):
      try await hid.sendButton(direction: direction, button: button)
    case let .keyboard(direction, keyCode):
      try await hid.sendKeyboard(direction: direction, keyCode: keyCode)
    case let .twoFingerTouch(direction, finger1, finger2):
      try await hid.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2)
    case let .trackpad(phase, point):
      try await hid.sendTrackpad(point: point, phase: phase)
    case let .delay(duration):
      try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
    case let .deviceOrientation(orientation):
      try hid.sendOrientation(orientation)
    case .shake:
      try hid.postDarwinNotification(shakeDarwinNotification)
    case .toggleInCallStatusBar:
      try hid.postDarwinNotification(inCallStatusBarNotification)
    case .lockDevice:
      try hid.sendLockDevice()
    case let .composite(events):
      for event in events {
        try await event.sendAsync(on: hid)
      }
    }
  }
}

public extension FBSimulatorHID {

  /// Sends a (possibly composite) HID event, then drains the transport exactly once.
  ///
  /// A `.composite` is flattened to its ordered sub-events so each is logged individually, and a
  /// `.delay` suspends the task; the single drain (`flush()`) then runs after the whole event. So a
  /// tap (down + up) or a typed string settles once, not after every primitive — which keeps the
  /// gesture intact before the connection is torn down while avoiding a per-primitive stall (e.g.
  /// slow typing on the DTUHID transport).
  func send(event: FBSimulatorHIDEvent, logger: FBControlCoreLogger) async throws {
    for subEvent in event.subEvents ?? [event] {
      switch subEvent {
      case let .delay(duration):
        logger.log("Delay \(duration)s")
        try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
      default:
        logger.log("Sending \(subEvent)")
        try await subEvent.sendAsync(on: self)
      }
    }
    // Only a gesture that wrote to the transport has anything to drain. Orientation, lock, shake and
    // the in-call status bar go out over Purple or as Darwin notifications, and a delay writes nothing
    // — draining after those buys nothing and costs `drainNanos` on DTUHID.
    if event.writesToTransport {
      try await flush()
    }
  }
}

// MARK: - Factories

public extension FBSimulatorHIDEvent {

  // Single-payload events use the enum cases directly (`.touch(direction:x:y:)`,
  // `.button(direction:button:)`, `.keyboard(direction:keyCode:)`, `.delay(_:)`,
  // `.deviceOrientation(_:)`, `.shake`, `.lockDevice`, `.toggleInCallStatusBar`, `.composite(_:)`).
  // Only composites with real construction logic are wrapped here.

  static func tapAt(x: Double, y: Double) -> FBSimulatorHIDEvent {
    .composite([
      .touch(direction: .down, x: x, y: y),
      .touch(direction: .up, x: x, y: y),
    ])
  }

  static func tapAt(x: Double, y: Double, duration: Double) -> FBSimulatorHIDEvent {
    .composite([
      .touch(direction: .down, x: x, y: y),
      .delay(duration),
      .touch(direction: .up, x: x, y: y),
    ])
  }

  static func shortButtonPress(_ button: FBSimulatorHIDButton) -> FBSimulatorHIDEvent {
    .composite([
      .button(direction: .down, button: button),
      .button(direction: .up, button: button),
    ])
  }

  static func shortKeyPress(_ keyCode: UInt32) -> FBSimulatorHIDEvent {
    .composite([
      .keyboard(direction: .down, keyCode: keyCode),
      .keyboard(direction: .up, keyCode: keyCode),
    ])
  }

  static func shortKeyPressSequence(_ sequence: [UInt32]) -> FBSimulatorHIDEvent {
    var events: [FBSimulatorHIDEvent] = []
    for keyCode in sequence {
      events.append(.keyboard(direction: .down, keyCode: keyCode))
      events.append(.keyboard(direction: .up, keyCode: keyCode))
    }
    return .composite(events)
  }

  /// A Siri Remote focus action for tvOS, delivered as the USB HID keyboard usage the tvOS focus
  /// engine consumes (arrows move focus, Return selects, Escape acts as Menu/back). The keyboard
  /// path is the universal baseline that works on the legacy Indigo transport.
  static func remoteButton(_ button: FBSimulatorHIDRemoteButton) -> FBSimulatorHIDEvent {
    shortKeyPress(button.keyboardUsage)
  }

  static func swipe(
    _ xStart: Double, yStart: Double, xEnd: Double, yEnd: Double, delta: Double, duration: Double
  ) -> FBSimulatorHIDEvent {
    var events: [FBSimulatorHIDEvent] = []
    let distance = sqrt(pow(yEnd - yStart, 2) + pow(xEnd - xStart, 2))
    var effectiveDelta = delta
    if effectiveDelta <= 0.0 {
      effectiveDelta = defaultSwipeDelta
    }
    let steps = max(1, Int(distance / effectiveDelta))

    let dx = (xEnd - xStart) / Double(steps)
    let dy = (yEnd - yStart) / Double(steps)

    let stepDelay = duration / Double(steps + 2)

    for i in 0...steps {
      events.append(.touch(direction: .down, x: xStart + dx * Double(i), y: yStart + dy * Double(i)))
      events.append(.delay(stepDelay))
    }
    // Add an additional touch down event at the end of the swipe to avoid inertial scroll on arm simulators.
    events.append(.touch(direction: .down, x: xStart + dx * Double(steps), y: yStart + dy * Double(steps)))
    events.append(.delay(stepDelay))

    events.append(.touch(direction: .up, x: xEnd, y: yEnd))

    return .composite(events)
  }

  /// A tvOS Siri Remote trackpad pan from `(fromX,fromY)` to `(toX,toY)` — points absolute-normalized
  /// (0..1, top-left). Expands to a began → changed×steps → ended gesture; the interpolated changed
  /// samples with small delays give the focus engine the velocity it needs to move focus. Drained once
  /// by `send(event:logger:)`. Indigo-only (the DTUHID transport has no trackpad).
  /// Interpolated samples stay inside the unit square because both endpoints do, so the intermediate
  /// points cannot fail to construct — hence the `?? from` fallbacks, which are unreachable.
  static func pan(
    from: FBSimulatorTrackpadPoint, to: FBSimulatorTrackpadPoint, steps: Int, duration: Double
  ) -> FBSimulatorHIDEvent {
    let n = max(1, steps)
    let stepDelay = duration / Double(n + 1)
    var events: [FBSimulatorHIDEvent] = [.trackpad(phase: .began, point: from)]
    for i in 1...n {
      let t = Double(i) / Double(n + 1)
      let sample =
        FBSimulatorTrackpadPoint(
          x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t
        ) ?? from
      events.append(.delay(stepDelay))
      events.append(.trackpad(phase: .changed, point: sample))
    }
    events.append(.delay(stepDelay))
    events.append(.trackpad(phase: .ended, point: to))
    return .composite(events)
  }

  static func pinchAt(
    x centerX: Double, y centerY: Double, scale: Double, duration: Double, radius: Double
  ) -> FBSimulatorHIDEvent {
    let startRadius = radius
    let endRadius = radius * scale
    let fingerDistance = abs(endRadius - startRadius)

    let delta = defaultSwipeDelta
    var steps = Int(fingerDistance / delta)
    if steps < 2 { steps = 2 }
    let stepDelay = duration / Double(steps + 2)

    var events: [FBSimulatorHIDEvent] = []

    // Touch down at start positions (fingers on horizontal axis centered on target)
    let f1Start = CGPoint(x: centerX - startRadius, y: centerY)
    let f2Start = CGPoint(x: centerX + startRadius, y: centerY)
    events.append(.twoFingerTouch(direction: .down, finger1: f1Start, finger2: f2Start))
    events.append(.delay(stepDelay))

    // Interpolated moves — same pattern as swipe
    let dr = (endRadius - startRadius) / Double(steps)
    for i in 1...steps {
      let r = startRadius + dr * Double(i)
      let f1 = CGPoint(x: centerX - r, y: centerY)
      let f2 = CGPoint(x: centerX + r, y: centerY)
      events.append(.twoFingerTouch(direction: .down, finger1: f1, finger2: f2))
      events.append(.delay(stepDelay))
    }

    // Duplicate final touch-down to avoid inertial scroll on arm simulators
    let f1End = CGPoint(x: centerX - endRadius, y: centerY)
    let f2End = CGPoint(x: centerX + endRadius, y: centerY)
    events.append(.twoFingerTouch(direction: .down, finger1: f1End, finger2: f2End))
    events.append(.delay(stepDelay))

    // Touch up at end positions
    events.append(.twoFingerTouch(direction: .up, finger1: f1End, finger2: f2End))

    return .composite(events)
  }
}

// MARK: - Remote button key mapping

private extension FBSimulatorHIDRemoteButton {
  /// The USB HID Keyboard/Keypad page (0x07) usage the tvOS focus engine consumes for this action.
  /// Live-confirmed on a booted Apple TV simulator: arrows move focus, Return selects, Escape backs out.
  var keyboardUsage: UInt32 {
    switch self {
    case .up: return 0x52
    case .down: return 0x51
    case .left: return 0x50
    case .right: return 0x4F
    case .select: return 0x28 // Return
    case .menu: return 0x29 // Escape
    }
  }
}

// MARK: - CustomStringConvertible

extension FBSimulatorHIDEvent: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .touch(direction, x, y):
      guard shouldLogHIDEventDetails() else { return "Touch <hidden>" }
      return "Touch \(direction.name) at (\(UInt(x)),\(UInt(y)))"
    case let .button(direction, button):
      guard shouldLogHIDEventDetails() else { return "Button <hidden>" }
      return "Button \(button.name) \(direction.name)"
    case let .keyboard(direction, keyCode):
      guard shouldLogHIDEventDetails() else { return "Key <hidden>" }
      return "Keyboard Code=\(keyCode) \(direction.name)"
    case let .twoFingerTouch(direction, finger1, finger2):
      guard shouldLogHIDEventDetails() else { return "TwoFingerTouch <hidden>" }
      return "TwoFingerTouch \(direction.name) at (\(finger1.x),\(finger1.y)) (\(finger2.x),\(finger2.y))"
    case let .trackpad(phase, point):
      guard shouldLogHIDEventDetails() else { return "Trackpad <hidden>" }
      return "Trackpad \(phase.name) at (\(point.x),\(point.y))"
    case let .delay(duration):
      return "Delay for \(duration)"
    case let .deviceOrientation(orientation):
      return "Set Orientation \(orientation.name)"
    case .shake:
      return "Shake"
    case .toggleInCallStatusBar:
      return "Toggle In-Call Status Bar"
    case .lockDevice:
      return "Lock Device"
    case let .composite(events):
      return "Composite [\(events.map { $0.description }.joined(separator: ", "))]"
    }
  }
}

// MARK: - Private helpers

private func shouldLogHIDEventDetails() -> Bool {
  ProcessInfo.processInfo.environment["FBSIMULATORCONTROL_LOG_HID_DETAILS"]?.boolValue ?? false
}

private extension String {
  var boolValue: Bool {
    (self as NSString).boolValue
  }
}
