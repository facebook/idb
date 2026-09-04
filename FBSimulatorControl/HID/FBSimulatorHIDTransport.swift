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

/// The transport carrying the Indigo-family HID primitives — touch, two-finger touch, button and
/// keyboard — and which of the two it is.
///
/// A closed enum rather than a protocol. There are exactly two, they are chosen at runtime, and they
/// differ in what they can carry. A protocol has to declare every capability on both, which is how
/// Indigo came to implement `flush()` as an empty body — it holds a synchronous client with nothing to
/// drain — and DTUHID to implement `sendTrackpad` only in order to throw. As cases, each capability
/// lives on the transport that has it and the caller switches for the rest.
///
/// Device orientation, lock, shake and the in-call status bar are not carried here at all. They are not
/// transport-switchable and go out over Purple mach messages and Darwin notifications.
enum FBSimulatorHIDTransport: Sendable {
  case indigo(FBSimulatorIndigoHIDTransport)
  case dtuhid(FBSimulatorDTUHIDTransport)

  /// Tears down any resources held by the transport.
  func disconnect() {
    switch self {
    case let .indigo(indigo): indigo.disconnect()
    case let .dtuhid(dtuhid): dtuhid.disconnect()
    }
  }

  /// Sends a single-finger touch at the given point (in points). `edge` tags the contact as
  /// originating at a screen edge, which is how the guest recognises a system edge gesture.
  func sendTouch(
    direction: FBSimulatorHIDDirection, x: Double, y: Double, edge: FBSimulatorHIDEdge
  ) async throws {
    switch self {
    case let .indigo(indigo): try await indigo.sendTouch(direction: direction, x: x, y: y, edge: edge)
    case let .dtuhid(dtuhid): try await dtuhid.sendTouch(direction: direction, x: x, y: y, edge: edge)
    }
  }

  /// Sends a two-finger touch (for multi-touch gestures) at the given points (in points).
  func sendTwoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws {
    switch self {
    case let .indigo(indigo):
      try await indigo.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2)
    case let .dtuhid(dtuhid):
      try await dtuhid.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2)
    }
  }

  /// Sends a hardware button event.
  func sendButton(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) async throws {
    switch self {
    case let .indigo(indigo): try await indigo.sendButton(direction: direction, button: button)
    case let .dtuhid(dtuhid): try await dtuhid.sendButton(direction: direction, button: button)
    }
  }

  /// Sends a keyboard key event.
  func sendKeyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32) async throws {
    switch self {
    case let .indigo(indigo): try await indigo.sendKeyboard(direction: direction, keyCode: keyCode)
    case let .dtuhid(dtuhid): try await dtuhid.sendKeyboard(direction: direction, keyCode: keyCode)
    }
  }
}
