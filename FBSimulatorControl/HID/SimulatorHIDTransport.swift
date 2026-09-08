/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// Selects which transport an `FBSimulatorHID` uses for the touch / button / keyboard primitives.
public enum FBSimulatorHIDTransportType: Equatable, Sendable {
  /// The legacy Indigo path via SimulatorKit's runtime-only `SimDeviceLegacyHIDClient`.
  case indigo
  /// The modern DTUHID path via the `dtuhidd` daemon (Xcode 27 / iOS 26+).
  case dtuhid
}

/// The transports driving a target: the one carrying the Indigo-family HID primitives — touch,
/// two-finger touch, button and keyboard — and, where a target needs both, the Indigo transport
/// running alongside it.
///
/// A closed enum rather than a protocol so each capability lives only on the transport that has it
/// (`flush` on DTUHID, `sendTrackpad` on Indigo) and callers switch for the rest.
///
/// Device orientation, lock, shake and the in-call status bar are not carried here at all. They are not
/// transport-switchable and go out over Purple mach messages and Darwin notifications.
///
/// A target can need both at once, which is `mixed`. `dtuhidd` exposes no trackpad, so an Apple TV
/// driven over DTUHID still reaches its Siri Remote trackpad over Indigo. Mixing is otherwise unsafe —
/// both claim `mainTouchscreen` and whichever sends first on a boot keeps it — so the case exists for
/// the one family with no touchscreen to contend over.
enum SimulatorHIDTransport: Sendable {
  /// Indigo alone, carrying the primitives and the trackpad.
  case indigo(SimulatorIndigoHIDTransport)
  /// DTUHID alone, carrying the primitives. No trackpad is reachable.
  case dtuhid(SimulatorDTUHIDTransport)
  /// Both, mixed on one target: DTUHID carrying the primitives, Indigo carrying only the trackpad.
  case mixed(dtuhid: SimulatorDTUHIDTransport, indigo: SimulatorIndigoHIDTransport)

  /// The Indigo transport in play, if any.
  var indigo: SimulatorIndigoHIDTransport? {
    switch self {
    case let .indigo(indigo): return indigo
    case .dtuhid: return nil
    case let .mixed(_, indigo): return indigo
    }
  }

  /// The DTUHID transport in play, if any.
  var dtuhid: SimulatorDTUHIDTransport? {
    switch self {
    case .indigo: return nil
    case let .dtuhid(dtuhid): return dtuhid
    case let .mixed(dtuhid, _): return dtuhid
    }
  }

  /// Tears down every transport held.
  func disconnect() {
    switch self {
    case let .indigo(indigo):
      indigo.disconnect()
    case let .dtuhid(dtuhid):
      dtuhid.disconnect()
    case let .mixed(dtuhid, indigo):
      dtuhid.disconnect()
      indigo.disconnect()
    }
  }

  /// Sends a single-finger touch at the given point (in points). `edge` tags the contact as
  /// originating at a screen edge, which is how the guest recognises a system edge gesture.
  func sendTouch(
    direction: FBSimulatorHIDDirection, x: Double, y: Double, edge: FBSimulatorHIDEdge
  ) async throws {
    switch self {
    case let .indigo(indigo): try await indigo.sendTouch(direction: direction, x: x, y: y, edge: edge)
    case let .dtuhid(dtuhid), let .mixed(dtuhid, _): try await dtuhid.sendTouch(direction: direction, x: x, y: y, edge: edge)
    }
  }

  /// Sends a two-finger touch (for multi-touch gestures) at the given points (in points).
  func sendTwoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws {
    switch self {
    case let .indigo(indigo):
      try await indigo.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2)
    case let .dtuhid(dtuhid), let .mixed(dtuhid, _):
      try await dtuhid.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2)
    }
  }

  /// Sends a hardware button event.
  func sendButton(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) async throws {
    switch self {
    case let .indigo(indigo): try await indigo.sendButton(direction: direction, button: button)
    case let .dtuhid(dtuhid), let .mixed(dtuhid, _): try await dtuhid.sendButton(direction: direction, button: button)
    }
  }

  /// Sends a keyboard key event.
  func sendKeyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32) async throws {
    switch self {
    case let .indigo(indigo): try await indigo.sendKeyboard(direction: direction, keyCode: keyCode)
    case let .dtuhid(dtuhid), let .mixed(dtuhid, _): try await dtuhid.sendKeyboard(direction: direction, keyCode: keyCode)
    }
  }

  /// Sends a tvOS Siri Remote focus action.
  func sendRemoteButton(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDRemoteButton) async throws {
    switch self {
    case let .indigo(indigo): try await indigo.sendRemoteButton(direction: direction, button: button)
    case let .dtuhid(dtuhid), let .mixed(dtuhid, _):
      try await dtuhid.sendRemoteButton(direction: direction, button: button)
    }
  }
}
