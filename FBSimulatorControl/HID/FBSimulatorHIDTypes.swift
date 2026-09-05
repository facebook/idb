/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// The core, transport-agnostic HID value types. Every transport (Indigo, DTUHID) and the
/// `FBSimulatorHIDEvent` dispatch share these; they are intentionally independent of any one
/// transport's wire format. Each carries a single canonical `name` — the source of truth for the
/// string forms used in event descriptions and (upper-cased) in CLI arguments.

/// The direction of a HID event.
public enum FBSimulatorHIDDirection: Int32, Sendable, CaseIterable {
  case down = 1
  case up = 2

  /// The canonical lower-snake-case name for this direction.
  public var name: String {
    switch self {
    case .down: return "down"
    case .up: return "up"
    }
  }
}

/// A hardware button press.
public enum FBSimulatorHIDButton: Int32, Sendable, CaseIterable {
  case applePay = 1
  case homeButton = 2
  case lock = 3
  case sideButton = 4
  case siri = 5
  case playPause = 6

  /// The canonical lower-snake-case name for this button.
  public var name: String {
    switch self {
    case .applePay: return "apple_pay"
    case .homeButton: return "home"
    case .lock: return "lock"
    case .sideButton: return "side_button"
    case .siri: return "siri"
    case .playPause: return "play_pause"
    }
  }
}

/// The screen edge a touch contact originated at.
///
/// iOS recognises its system edge gestures — the home indicator swipe, Notification Centre, the
/// back swipe — from a flag on the digitizer contact, not from where the contact happens to be. A
/// swipe that merely starts at `y = height` is an ordinary swipe; one tagged with `.bottom` is the
/// home gesture. Each transport encodes this its own way (see `Indigo.h` for the wire values).
///
/// Named for where the gesture *starts*, not which way it travels: `.bottom` is a swipe up from the
/// bottom edge.
public enum FBSimulatorHIDEdge: UInt32, Sendable, CaseIterable {
  case none = 0
  case top = 1
  case left = 2
  case bottom = 3
  case right = 4

  /// The canonical lower-snake-case name for this edge.
  public var name: String {
    switch self {
    case .none: return "none"
    case .top: return "top"
    case .left: return "left"
    case .bottom: return "bottom"
    case .right: return "right"
    }
  }
}

/// A Siri Remote action for tvOS focus navigation. The focus-step actions map to USB HID keyboard
/// usages the tvOS focus engine already consumes; this is the transport-agnostic vocabulary callers
/// use, independent of how a given transport delivers it.
public enum FBSimulatorHIDRemoteButton: Int32, Sendable, CaseIterable {
  case up = 1
  case down = 2
  case left = 3
  case right = 4
  case select = 5
  case menu = 6

  /// The canonical lower-snake-case name for this remote action.
  public var name: String {
    switch self {
    case .up: return "up"
    case .down: return "down"
    case .left: return "left"
    case .right: return "right"
    case .select: return "select"
    case .menu: return "menu"
    }
  }
}

/// A point on the tvOS Siri Remote trackpad surface, in absolute-normalized coordinates: `(0, 0)` is
/// the top-left of the surface and `(1, 1)` the bottom-right.
///
/// A distinct type from `CGPoint` so trackpad (unit-square) and screen points cannot be confused.
public struct FBSimulatorTrackpadPoint: Equatable, Hashable, Sendable {

  public let x: Double
  public let y: Double

  /// Fails outside the unit square rather than clamping. A caller passing screen coordinates has a
  /// bug, and quietly landing the gesture in a corner hides it.
  public init?(x: Double, y: Double) {
    guard (0...1).contains(x), (0...1).contains(y) else {
      return nil
    }
    self.x = x
    self.y = y
  }
}

/// The phase of a tvOS Siri Remote trackpad gesture. A pan is a began → changed×N → ended sequence;
/// the phase selects which digitizer fields the Indigo trackpad message carries so the tvOS focus
/// engine reads a lifting gesture (a bare stream of positions never moves focus).
public enum FBSimulatorTrackpadPhase: Sendable, Equatable, Hashable, CaseIterable {
  case began
  case changed
  case ended

  /// The canonical lower-snake-case name for this phase.
  public var name: String {
    switch self {
    case .began: return "began"
    case .changed: return "changed"
    case .ended: return "ended"
    }
  }
}

/// Device orientation. Values match UIDeviceOrientation (1-4, excluding faceUp/faceDown).
public enum FBSimulatorHIDDeviceOrientation: Int32, Sendable, CaseIterable {
  case portrait = 1
  case portraitUpsideDown = 2
  case landscapeRight = 3
  case landscapeLeft = 4

  /// The canonical lower-snake-case name for this orientation.
  public var name: String {
    switch self {
    case .portrait: return "portrait"
    case .portraitUpsideDown: return "portrait_upside_down"
    case .landscapeRight: return "landscape_right"
    case .landscapeLeft: return "landscape_left"
    }
  }
}
