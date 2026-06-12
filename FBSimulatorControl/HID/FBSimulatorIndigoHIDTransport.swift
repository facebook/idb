/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@preconcurrency import CoreSimulator
import Darwin
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
  /// The simulator's UDID, used to locate its `launchd_sim` for the legacy-keyboard-suppression check.
  private let simulatorUDID: String
  /// Cached legacy-keyboard-suppression result (see `legacyKeyboardSuppressed()`).
  private var cachedKeyboardSuppressed: Bool?

  // MARK: Initializers

  /// Creates a transport for the provided Simulator, registering a HID client.
  /// Will fail if a HID Port could not be registered for the provided Simulator.
  /// Registration may need to occur prior to booting.
  static func indigo(for simulator: FBSimulator) throws -> FBSimulatorIndigoHIDTransport {
    FBSimulatorIndigoHIDTransport(
      indigoClient: try FBSimulatorIndigoHIDClient.client(for: simulator.device),
      indigo: try FBSimulatorIndigoHID.simulatorKitHID(),
      mainScreenSize: simulator.device.deviceType.mainScreenSize,
      mainScreenScale: simulator.device.deviceType.mainScreenScale,
      simulatorUDID: simulator.udid)
  }

  init(
    indigoClient: FBSimulatorIndigoHIDClient,
    indigo: FBSimulatorIndigoHID,
    mainScreenSize: CGSize,
    mainScreenScale: Float,
    simulatorUDID: String
  ) {
    self.indigoClient = indigoClient
    self.indigo = indigo
    self.mainScreenSize = mainScreenSize
    self.mainScreenScale = mainScreenScale
    self.simulatorUDID = simulatorUDID
  }

  // MARK: FBSimulatorHIDTransport

  nonisolated func disconnect() {
    indigoClient.disconnect()
  }

  func sendTouch(direction: FBSimulatorHIDDirection, x: Double, y: Double) async throws {
    try await indigoClient.send(
      indigo.touchScreenSize(mainScreenSize, screenScale: mainScreenScale, direction: direction, x: x, y: y))
  }

  func sendTwoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws {
    try await indigoClient.send(
      indigo.twoFingerTouchScreenSize(
        mainScreenSize, screenScale: mainScreenScale, direction: direction, finger1: finger1, finger2: finger2))
  }

  func sendButton(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) async throws {
    try await indigoClient.send(indigo.button(with: direction, button: button))
  }

  func sendKeyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32) async throws {
    // On Xcode 27 (CoreSimulator-1155.4)+ an active dtuhidd disconnects the legacy
    // `ExternalKeyboardService`, so legacy keyboard events deliver byte-correctly but produce no
    // text. Fail loudly rather than typing into the void — the DTUHID transport is the workaround.
    if legacyKeyboardSuppressed() {
      throw FBSimulatorHIDError.keyboardSuppressedByActiveDTUHIDD
    }
    try await indigoClient.send(indigo.keyboard(with: direction, keyCode: keyCode))
  }

  // MARK: Legacy keyboard suppression

  /// Whether the legacy keyboard HID service is suppressed for this transport's simulator.
  ///
  /// On Xcode 27 (CoreSimulator-1155.4) and later, the host-injected SimulatorHID disconnects the
  /// legacy `ExternalKeyboardService` while `dtuhidd` is active, so legacy keyboard events are
  /// delivered byte-correctly but produce no text (touch and the other services are unaffected).
  /// Cached for this transport's lifetime — the dominant case is a simulator already poisoned at
  /// connect time, and re-reading per key would re-walk the host process tree on every keystroke.
  /// The actor serializes access, so the cache needs no further locking.
  private func legacyKeyboardSuppressed() -> Bool {
    if let cachedKeyboardSuppressed {
      return cachedKeyboardSuppressed
    }
    let suppressed = computeLegacyKeyboardSuppressed()
    cachedKeyboardSuppressed = suppressed
    return suppressed
  }

  private func computeLegacyKeyboardSuppressed() -> Bool {
    // Only CoreSimulator-1155.4+ (Xcode 27) ships the dtuhidd suppression machinery; older
    // toolchains have no `dtuhidd`, so skip the process-tree walk entirely.
    guard let version = FBSimulatorControlFrameworkLoader.loadedCoreSimulatorVersion,
      version.compare("1155.4", options: .numeric) != .orderedAscending
    else {
      return false
    }
    // `dtuhidd` runs as a child of the simulator's `launchd_sim`; its presence in the simulator's
    // process subtree is the per-simulator signal. Read host-side (the authoritative guest notify
    // state `com.apple.coredevice.dtuhidd.active` is not host-bridged).
    return launchdSimSubprocessIdentifier(named: "dtuhidd", forSimulatorUDID: simulatorUDID) != nil
  }
}

// MARK: - Simulator process tree

/// The host `launchd_sim` process backing the simulator with `udid`, matched by the UDID in its
/// arguments, or `nil` if it cannot be found (e.g. the simulator is not booted).
private func launchdSimProcess(forSimulatorUDID udid: String, using fetcher: FBProcessFetcher = FBProcessFetcher()) -> FBProcessInfo? {
  fetcher.processes(withProcessName: "launchd_sim").first { process in
    process.arguments.contains { $0.contains(udid) }
  }
}

/// The process identifier of a subprocess of the simulator's `launchd_sim` whose name contains
/// `name`, or `nil` if there is none. A purely host-side query of the simulator's process subtree.
private func launchdSimSubprocessIdentifier(named name: String, forSimulatorUDID udid: String, using fetcher: FBProcessFetcher = FBProcessFetcher()) -> pid_t? {
  guard let launchdSim = launchdSimProcess(forSimulatorUDID: udid, using: fetcher) else {
    return nil
  }
  let identifier = fetcher.subprocess(of: launchdSim.processIdentifier, withName: name)
  return identifier > 0 ? identifier : nil
}

// MARK: - Loaded CoreSimulator version

/// Kept private to the HID layer (its only consumer): the loaded framework version, read here rather
/// than swiftifying the Objective-C framework loader (a separate concern).
private extension FBSimulatorControlFrameworkLoader {

  /// The version of the CoreSimulator framework actually loaded in-process (e.g. `"1155.4"`), read
  /// from the bundle that vends `SimDevice`, or `nil` if it is not loaded. CoreSimulator is a system
  /// framework that the Xcode installer overwrites, so the loaded framework can differ from the
  /// selected Xcode; behaviour gated on a CoreSimulator version must consult this, not the Xcode one.
  static var loadedCoreSimulatorVersion: String? {
    guard let simDeviceClass = NSClassFromString("SimDevice") else {
      return nil
    }
    return Bundle(for: simDeviceClass).infoDictionary?["CFBundleVersion"] as? String
  }
}
