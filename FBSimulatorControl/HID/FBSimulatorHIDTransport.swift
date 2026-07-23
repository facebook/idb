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

/// A transport for the Indigo-family HID primitives (touch, two-finger touch, button, keyboard).
///
/// `FBSimulatorHID` routes exactly these four primitives through the selected transport. Device
/// orientation, lock, shake, and the in-call status bar are not transport-switchable and stay on
/// `FBSimulatorHID`'s Purple / Darwin paths.
///
/// Conformers serialize their own sends, so the protocol refines `Sendable`.
protocol FBSimulatorHIDTransport: Sendable {
  /// Tears down any resources held by the transport.
  func disconnect()
  /// Sends a single-finger touch at the given point (in points).
  func sendTouch(direction: FBSimulatorHIDDirection, x: Double, y: Double) async throws
  /// Sends a two-finger touch (for multi-touch gestures) at the given points (in points).
  func sendTwoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws
  /// Sends a hardware button event.
  func sendButton(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) async throws
  /// Sends a keyboard key event.
  func sendKeyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32) async throws
  /// Sends one phase of a tvOS Siri Remote trackpad gesture. `point` is absolute-normalized (0..1).
  /// Indigo-only: the trackpad rides the dedicated Indigo trackpad service, which the `dtuhidd` daemon
  /// does not expose (the DTUHID impl throws `notImplementedOnDTUHIDTransport`).
  func sendTrackpad(point: CGPoint, phase: FBSimulatorTrackpadPhase) async throws
  /// Drains the transport after a gesture's events have all been sent, so the daemon consumes them
  /// before the connection is torn down. Called once per dispatched `FBSimulatorHIDEvent` (i.e. once
  /// per gesture), not once per primitive.
  func flush() async throws
}
