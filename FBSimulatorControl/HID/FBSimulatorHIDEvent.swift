/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

public let DEFAULT_SWIPE_DELTA: Double = 10.0

private let shakeDarwinNotification = "com.apple.UIKit.SimulatorShake"
private let inCallStatusBarNotification = "com.apple.iphonesimulator.toggleincallstatusbar"

// MARK: - FBSimulatorHIDEvent

/// A HID event that can be sent to a Simulator. A discriminated union of the primitive
/// payloads (touch, button, keyboard, two-finger touch, orientation, shake, lock, in-call
/// status bar, delay) plus a `composite` of ordered events.
public indirect enum FBSimulatorHIDEvent: Equatable, Hashable {
  case touch(direction: FBSimulatorHIDDirection, x: Double, y: Double)
  case button(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton)
  case keyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32)
  case twoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint)
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
    case let .delay(duration):
      try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
    case let .deviceOrientation(orientation):
      try hid.sendPurpleEvent(hid.purple.orientationEvent(orientation))
    case .shake:
      try hid.postDarwinNotification(shakeDarwinNotification)
    case .toggleInCallStatusBar:
      try hid.postDarwinNotification(inCallStatusBarNotification)
    case .lockDevice:
      try hid.sendPurpleEvent(hid.purple.lockDeviceEvent())
    case let .composite(events):
      for event in events {
        try await event.sendAsync(on: hid)
      }
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

  static func shortKeyPressSequence(_ sequence: [NSNumber]) -> FBSimulatorHIDEvent {
    var events: [FBSimulatorHIDEvent] = []
    for keyCode in sequence {
      events.append(.keyboard(direction: .down, keyCode: keyCode.uint32Value))
      events.append(.keyboard(direction: .up, keyCode: keyCode.uint32Value))
    }
    return .composite(events)
  }

  static func swipe(
    _ xStart: Double, yStart: Double, xEnd: Double, yEnd: Double, delta: Double, duration: Double
  ) -> FBSimulatorHIDEvent {
    var events: [FBSimulatorHIDEvent] = []
    let distance = sqrt(pow(yEnd - yStart, 2) + pow(xEnd - xStart, 2))
    var effectiveDelta = delta
    if effectiveDelta <= 0.0 {
      effectiveDelta = DEFAULT_SWIPE_DELTA
    }
    let steps = Int(distance / effectiveDelta)

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

  static func pinchAt(
    x centerX: Double, y centerY: Double, scale: Double, duration: Double, radius: Double
  ) -> FBSimulatorHIDEvent {
    let startRadius = radius
    let endRadius = radius * scale
    let fingerDistance = abs(endRadius - startRadius)

    let delta = DEFAULT_SWIPE_DELTA
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

// MARK: - CustomStringConvertible

extension FBSimulatorHIDEvent: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .touch(direction, x, y):
      guard shouldLogHIDEventDetails() else { return "Touch <hidden>" }
      return "Touch \(directionString(direction)) at (\(UInt(x)),\(UInt(y)))"
    case let .button(direction, button):
      guard shouldLogHIDEventDetails() else { return "Button <hidden>" }
      return "Button \(buttonString(button)) \(directionString(direction))"
    case let .keyboard(direction, keyCode):
      guard shouldLogHIDEventDetails() else { return "Key <hidden>" }
      return "Keyboard Code=\(keyCode) \(directionString(direction))"
    case let .twoFingerTouch(direction, finger1, finger2):
      guard shouldLogHIDEventDetails() else { return "TwoFingerTouch <hidden>" }
      return "TwoFingerTouch \(directionString(direction)) at (\(finger1.x),\(finger1.y)) (\(finger2.x),\(finger2.y))"
    case let .delay(duration):
      return "Delay for \(duration)"
    case let .deviceOrientation(orientation):
      return "Set Orientation \(orientationString(orientation))"
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

private func directionString(_ direction: FBSimulatorHIDDirection) -> String {
  switch direction {
  case .down:
    return "down"
  case .up:
    return "up"
  }
}

private func buttonString(_ button: FBSimulatorHIDButton) -> String {
  switch button {
  case .applePay:
    return "apple_pay"
  case .homeButton:
    return "home"
  case .lock:
    return "lock"
  case .sideButton:
    return "side"
  case .siri:
    return "siri"
  }
}

private func orientationString(_ orientation: FBSimulatorHIDDeviceOrientation) -> String {
  switch orientation {
  case .portrait:
    return "portrait"
  case .portraitUpsideDown:
    return "portrait_upside_down"
  case .landscapeRight:
    return "landscape_right"
  case .landscapeLeft:
    return "landscape_left"
  }
}
