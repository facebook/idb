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

 Builds `IndigoMessage` payloads with `FBSimulatorIndigoHID` and delivers them through the runtime-only
 `SimDeviceLegacyHIDClient` (owned by `FBSimulatorIndigoHIDClient`). Guest-side:
 `SimHIDVirtualServiceManager` dispatches on eventKind + target. See `Indigo.h` for wire format.

 An `actor`, so sends are serialized by actor isolation (no `@unchecked Sendable`).
 */
actor FBSimulatorIndigoHIDTransport: FBSimulatorHIDTransport {

  /// Delivers the built Indigo message bytes to the simulator. `Sendable`, so `disconnect()` can
  /// reach it from a `nonisolated` context.
  private let indigoClient: FBSimulatorIndigoHIDClient
  /// The Indigo payload builder (touch, button, keyboard).
  private let indigo: FBSimulatorIndigoHID
  /// The dimensions of the main screen.
  private let mainScreenSize: CGSize
  /// The scale of the main screen.
  private let mainScreenScale: Float
  /// Whether an active `dtuhidd` has suppressed this simulator's legacy keyboard HID, captured from
  /// `FBSimulator.isLegacyHIDSuppressed` when the transport is built. `sendKeyboard` fails loudly on
  /// it rather than typing into the void; the DTUHID transport is the workaround.
  private let legacyKeyboardSuppressed: Bool
  /// The product family of the target, captured at construction. Touchscreen touches are a no-op on
  /// tvOS (it has no digitizer), so the touch primitives reject `AppleTV` rather than failing silently.
  private let productFamily: FBControlCoreProductFamily

  // MARK: Initializers

  /// Creates a transport for the provided Simulator, registering a HID client.
  /// Will fail if a HID Port could not be registered for the provided Simulator.
  /// Registration may need to occur prior to booting.
  static func indigo(for simulator: FBSimulator) throws -> FBSimulatorIndigoHIDTransport {
    FBSimulatorIndigoHIDTransport(
      indigoClient: try FBSimulatorIndigoHIDClient(for: simulator.device),
      indigo: try FBSimulatorIndigoHID(),
      mainScreenSize: simulator.device.deviceType.mainScreenSize,
      mainScreenScale: simulator.device.deviceType.mainScreenScale,
      legacyKeyboardSuppressed: simulator.isLegacyHIDSuppressed,
      productFamily: simulator.productFamily)
  }

  init(
    indigoClient: FBSimulatorIndigoHIDClient,
    indigo: FBSimulatorIndigoHID,
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

  // MARK: FBSimulatorHIDTransport

  nonisolated func disconnect() {
    indigoClient.disconnect()
  }

  func sendTouch(direction: FBSimulatorHIDDirection, x: Double, y: Double) async throws {
    if productFamily == .familyAppleTV {
      throw FBSimulatorHIDError.touchUnsupportedOnAppleTV
    }
    try await indigoClient.send(
      indigo.touchScreenSize(mainScreenSize, screenScale: mainScreenScale, direction: direction, x: x, y: y))
  }

  func sendTwoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws {
    if productFamily == .familyAppleTV {
      throw FBSimulatorHIDError.touchUnsupportedOnAppleTV
    }
    try await indigoClient.send(
      indigo.twoFingerTouchScreenSize(
        mainScreenSize, screenScale: mainScreenScale, direction: direction, finger1: finger1, finger2: finger2))
  }

  func sendButton(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) async throws {
    guard let data = indigo.button(with: direction, button: button) else {
      throw FBSimulatorHIDError.notImplementedOnIndigoTransport(
        operation: "sendButton(.\(button.name)) — a Consumer-page button with no legacy Indigo source; use the DTUHID transport")
    }
    try await indigoClient.send(data)
  }

  func sendKeyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32) async throws {
    // On Xcode 27 (CoreSimulator-1155.4)+ an active dtuhidd disconnects the legacy
    // `ExternalKeyboardService`, so legacy keyboard events deliver byte-correctly but produce no
    // text. Fail loudly rather than typing into the void — the DTUHID transport is the workaround.
    if legacyKeyboardSuppressed {
      throw FBSimulatorHIDError.keyboardSuppressedByActiveDTUHIDD
    }
    try await indigoClient.send(indigo.keyboard(with: direction, keyCode: keyCode))
  }

  /// No-op: the legacy client awaits delivery on every `send`, so there is nothing left to drain.
  func flush() async throws {}

  // No tvOS guard — the trackpad is exactly what Apple TV targets need (unlike the touchscreen).
  func sendTrackpad(point: CGPoint, phase: FBSimulatorTrackpadPhase) async throws {
    try await indigoClient.send(indigo.trackpad(point: point, phase: phase))
  }
}
