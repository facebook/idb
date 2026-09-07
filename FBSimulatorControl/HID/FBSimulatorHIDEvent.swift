/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

// MARK: - FBSimulatorHIDEvent

/// A HID event that can be sent to a Simulator. A discriminated union of the primitive
/// payloads (touch, button, keyboard, two-finger touch, orientation, shake, lock, in-call
/// status bar, delay) plus a `composite` of ordered events.
public indirect enum FBSimulatorHIDEvent: Equatable, Hashable, Sendable {

  /// The per-sample step, in points, a swipe is broken into when the caller does not choose one.
  public static let defaultSwipeDelta: Double = 10.0

  case touch(direction: FBSimulatorHIDDirection, x: Double, y: Double, edge: FBSimulatorHIDEdge)
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

}

// MARK: - Dispatch

public extension FBSimulatorHIDEvent {

  /// Sends without draining afterwards. Prefer `FBSimulatorHID.send(event:logger:)`, which drains once per gesture.
  func send(on hid: FBSimulatorHID) async throws {
    _ = try await hid.deliver(self)
  }
}

// MARK: - Factories

public extension FBSimulatorHIDEvent {

  /// An ordinary touch, not originating at a screen edge — what almost every caller wants. Tagging a
  /// contact with an edge is what turns a swipe into a system gesture, so it has to be asked for
  /// explicitly via the `.touch` case.
  static func touch(direction: FBSimulatorHIDDirection, x: Double, y: Double) -> FBSimulatorHIDEvent {
    .touch(direction: direction, x: x, y: y, edge: .none)
  }

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

  /// A swipe from `(xStart,yStart)` to `(xEnd,yEnd)`, interpolated at `delta` points per sample.
  ///
  /// `edge` tags every contact in the gesture, not just the first: the guest reads the edge flag off
  /// whichever contact it is inspecting, so a gesture that announced an edge only on touch-down would
  /// be read as an ordinary drag from its second sample onwards.
  static func swipe(
    _ xStart: Double, yStart: Double, xEnd: Double, yEnd: Double, delta: Double, duration: Double,
    edge: FBSimulatorHIDEdge = .none
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
      events.append(.touch(direction: .down, x: xStart + dx * Double(i), y: yStart + dy * Double(i), edge: edge))
      events.append(.delay(stepDelay))
    }
    // Add an additional touch down event at the end of the swipe to avoid inertial scroll on arm simulators.
    events.append(
      .touch(direction: .down, x: xStart + dx * Double(steps), y: yStart + dy * Double(steps), edge: edge))
    events.append(.delay(stepDelay))

    events.append(.touch(direction: .up, x: xEnd, y: yEnd, edge: edge))

    return .composite(events)
  }

  /// How far across the screen an edge swipe travels, as a fraction of the axis it moves along. Half
  /// the screen is comfortably past the thresholds the system gestures commit at, without running the
  /// contact into the opposite edge.
  static let edgeSwipeTravelFraction: Double = 0.5

  /// A swipe inwards from a screen edge — the gesture iOS reads as a system gesture rather than as
  /// content scrolling: up from the bottom for the home indicator, down from the top for Notification
  /// Centre, rightwards from the left edge for back.
  ///
  /// `screenSize` is in points. The gesture starts one point inside the edge rather than exactly on it,
  /// because the far edge of the screen is `size - 1` in a coordinate space that starts at zero, and
  /// travels `edgeSwipeTravelFraction` of the way across.
  ///
  /// `.none` is accepted and produces a stationary contact at the screen centre with no edge flag, so
  /// a caller threading an edge through from a CLI argument does not have to special-case it.
  static func edgeSwipe(
    _ edge: FBSimulatorHIDEdge, screenSize: CGSize, duration: Double, delta: Double = defaultSwipeDelta
  ) -> FBSimulatorHIDEvent {
    let width = Double(screenSize.width)
    let height = Double(screenSize.height)
    let midX = width / 2
    let midY = height / 2
    let travelX = width * edgeSwipeTravelFraction
    let travelY = height * edgeSwipeTravelFraction

    let start: CGPoint
    let end: CGPoint
    switch edge {
    case .top:
      start = CGPoint(x: midX, y: 1)
      end = CGPoint(x: midX, y: travelY)
    case .bottom:
      start = CGPoint(x: midX, y: height - 1)
      end = CGPoint(x: midX, y: height - travelY)
    case .left:
      start = CGPoint(x: 1, y: midY)
      end = CGPoint(x: travelX, y: midY)
    case .right:
      start = CGPoint(x: width - 1, y: midY)
      end = CGPoint(x: width - travelX, y: midY)
    case .none:
      start = CGPoint(x: midX, y: midY)
      end = CGPoint(x: midX, y: midY)
    }

    return swipe(
      Double(start.x), yStart: Double(start.y), xEnd: Double(end.x), yEnd: Double(end.y),
      delta: delta, duration: duration, edge: edge)
  }

  /// A press-and-drag: hold at the source for `pressDuration`, travel over interpolated samples spread
  /// across `duration`, hold at the destination for `releaseDuration`, then lift. The initial hold is what
  /// starts an iOS drag session (it must clear the long-press threshold); `swipe` cannot express it.
  static func drag(
    _ xStart: Double, yStart: Double, xEnd: Double, yEnd: Double, delta: Double,
    pressDuration: Double, duration: Double, releaseDuration: Double
  ) -> FBSimulatorHIDEvent {
    let distance = sqrt(pow(yEnd - yStart, 2) + pow(xEnd - xStart, 2))
    var effectiveDelta = delta
    if effectiveDelta <= 0.0 {
      effectiveDelta = defaultSwipeDelta
    }
    let steps = max(1, Int(distance / effectiveDelta))

    let dx = (xEnd - xStart) / Double(steps)
    let dy = (yEnd - yStart) / Double(steps)
    let stepDelay = duration / Double(steps)

    var events: [FBSimulatorHIDEvent] = [
      .touch(direction: .down, x: xStart, y: yStart),
      .delay(pressDuration),
    ]
    for i in 1...steps {
      events.append(.touch(direction: .down, x: xStart + dx * Double(i), y: yStart + dy * Double(i)))
      events.append(.delay(stepDelay))
    }
    events.append(.delay(releaseDuration))
    events.append(.touch(direction: .up, x: xEnd, y: yEnd))

    return .composite(events)
  }

  /// A tvOS Siri Remote trackpad pan (unit-square points): began → changed×steps → ended, with small delays
  /// so the focus engine sees velocity. Indigo only. The `?? from` fallbacks are unreachable — interpolating
  /// two in-square points stays in the square.
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

    let f1Start = CGPoint(x: centerX - startRadius, y: centerY)
    let f2Start = CGPoint(x: centerX + startRadius, y: centerY)
    events.append(.twoFingerTouch(direction: .down, finger1: f1Start, finger2: f2Start))
    events.append(.delay(stepDelay))

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
    case let .touch(direction, x, y, edge):
      guard shouldLogHIDEventDetails() else { return "Touch <hidden>" }
      guard edge != .none else { return "Touch \(direction.name) at (\(x),\(y))" }
      return "Touch \(direction.name) at (\(x),\(y)) from the \(edge.name) edge"
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
