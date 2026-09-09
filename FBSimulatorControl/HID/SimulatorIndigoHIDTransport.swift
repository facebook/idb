/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

/**
 The default HID transport (IndigoHIDRegistrationPort).

 Builds `IndigoMessage` payloads with `SimulatorIndigoHID` and delivers them through the runtime-only
 `SimDeviceLegacyHIDClient` (owned by `SimulatorIndigoHIDClient`). Guest-side:
 `SimHIDVirtualServiceManager` dispatches on eventKind + target. See `Indigo.h` for wire format.

 An `actor`, so sends are serialized by actor isolation (no `@unchecked Sendable`).
 */
actor SimulatorIndigoHIDTransport {

  /// Delivers the built Indigo message bytes to the simulator. `Sendable`, so `disconnect()` can
  /// reach it from a `nonisolated` context.
  private let indigoClient: SimulatorIndigoHIDClient
  /// The Indigo payload builder (touch, button, keyboard).
  private let indigo: SimulatorIndigoHID
  /// The dimensions of the main screen.
  private let mainScreenSize: CGSize
  /// The scale of the main screen.
  private let mainScreenScale: Float
  /// Whether the guest has handed its legacy keyboard HID over to `dtuhidd`, captured from
  /// `FBSimulator.isLegacyKeyboardSuppressed` when the transport is built. `sendKeyboard` fails loudly on
  /// it rather than typing into the void; the DTUHID transport is the workaround.
  private let legacyKeyboardSuppressed: Bool
  /// The product family of the target, captured at construction. Touchscreen touches are a no-op on
  /// tvOS (it has no digitizer), so the touch primitives reject `AppleTV` rather than failing silently.
  private let productFamily: FBControlCoreProductFamily

  /// Creates a transport for the provided Simulator, registering a HID client.
  /// Will fail if a HID Port could not be registered for the provided Simulator.
  /// Registration may need to occur prior to booting.
  static func indigo(for simulator: FBSimulator) throws -> SimulatorIndigoHIDTransport {
    SimulatorIndigoHIDTransport(
      indigoClient: try SimulatorIndigoHIDClient(for: simulator.device),
      indigo: try SimulatorIndigoHID(),
      mainScreenSize: simulator.device.deviceType.mainScreenSize,
      mainScreenScale: simulator.device.deviceType.mainScreenScale,
      legacyKeyboardSuppressed: simulator.isLegacyKeyboardSuppressed,
      productFamily: simulator.productFamily)
  }

  init(
    indigoClient: SimulatorIndigoHIDClient,
    indigo: SimulatorIndigoHID,
    mainScreenSize: CGSize,
    mainScreenScale: Float,
    legacyKeyboardSuppressed: Bool,
    productFamily: FBControlCoreProductFamily
  ) {
    self.indigoClient = indigoClient
    self.indigo = indigo
    self.mainScreenSize = mainScreenSize
    self.mainScreenScale = mainScreenScale
    self.legacyKeyboardSuppressed = legacyKeyboardSuppressed
    self.productFamily = productFamily
  }

  // MARK: - Sends

  nonisolated func disconnect() {
    indigoClient.disconnect()
  }

  func sendTouch(
    direction: SimulatorHIDDirection, x: Double, y: Double, edge: FBSimulatorHIDEdge
  ) async throws {
    guard productFamily.hasTouchscreen else {
      throw SimulatorHIDError.touchUnsupportedOnAppleTV
    }
    try await indigoClient.send(
      indigo.touchScreenSize(
        mainScreenSize, screenScale: mainScreenScale, direction: direction, x: x, y: y, edge: edge))
  }

  func sendTwoFingerTouch(direction: SimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws {
    guard productFamily.hasTouchscreen else {
      throw SimulatorHIDError.touchUnsupportedOnAppleTV
    }
    try await indigoClient.send(
      indigo.twoFingerTouchScreenSize(
        mainScreenSize, screenScale: mainScreenScale, direction: direction, finger1: finger1, finger2: finger2))
  }

  func sendButton(direction: SimulatorHIDDirection, button: FBSimulatorHIDButton) async throws {
    try await indigoClient.send(indigo.button(with: direction, button: button))
  }

  func sendKeyboard(direction: SimulatorHIDDirection, keyCode: UInt32) async throws {
    // On Xcode 27 (CoreSimulator-1155.4)+ the guest disconnects the legacy `ExternalKeyboardService`
    // in favour of dtuhidd, so legacy keyboard events deliver byte-correctly but produce no text.
    if legacyKeyboardSuppressed {
      throw SimulatorHIDError.keyboardSuppressedByDTUHIDD
    }
    try await indigoClient.send(indigo.keyboard(with: direction, keyCode: keyCode))
  }

  /// Delivers a Siri Remote focus action as the keyboard usage the tvOS focus engine consumes, which is
  /// the only encoding the legacy path has for it — so it is subject to the same Xcode 27 suppression.
  func sendRemoteButton(direction: SimulatorHIDDirection, button: FBSimulatorHIDRemoteButton) async throws {
    try await sendKeyboard(direction: direction, keyCode: button.keyboardUsage)
  }

  // No tvOS guard — the trackpad is exactly what Apple TV targets need (unlike the touchscreen).
  func sendTrackpad(point: FBSimulatorTrackpadPoint, phase: SimulatorTrackpadPhase) async throws {
    try await indigoClient.send(indigo.trackpad(point: CGPoint(x: point.x, y: point.y), phase: phase))
  }
}
