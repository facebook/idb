/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Darwin
@preconcurrency import FBControlCore
import Foundation

// MARK: - Transport selection policy

/// Decides which HID transport a caller that did not request one gets, and whether the legacy Indigo
/// path is functional at all.
///
/// A namespace of pure functions over injected host facts rather than methods on `FBSimulator`, so
/// the policy is unit-testable without a booted simulator. `FBSimulator` supplies the real facts in
/// the adapter below.
enum FBSimulatorHIDTransportSelection {

  /// The first CoreSimulator version to inject `dtuhidd` into the guest. Older toolchains have no
  /// DTUHID transport at all.
  static let firstDTUHIDCoreSimulatorVersion = "1155.4"

  /// Whether `coreSimulatorVersion` is new enough to ship `dtuhidd`. Compared numerically, so that
  /// `1155.10` sorts above `1155.4` rather than lexicographically below it.
  static func shipsDTUHID(coreSimulatorVersion: String?) -> Bool {
    guard let coreSimulatorVersion else {
      return false
    }
    return coreSimulatorVersion.compare(firstDTUHIDCoreSimulatorVersion, options: .numeric) != .orderedAscending
  }

  /// Whether `productFamily` can be driven over DTUHID at all.
  ///
  /// The tvOS Siri Remote trackpad rides a dedicated Indigo trackpad service that `dtuhidd` does not
  /// expose — its digitizer targets are displays and its scroll targets are rotary devices — so Apple
  /// TV targets have to stay on Indigo to keep the remote working.
  static func supportsDTUHID(productFamily: FBControlCoreProductFamily) -> Bool {
    productFamily != .familyAppleTV
  }

  /// Whether an active `dtuhidd` has suppressed this simulator's legacy HID services.
  static func isLegacyHIDSuppressed(
    coreSimulatorVersion: String?,
    isDTUHIDDRunning: () -> Bool
  ) -> Bool {
    // Only CoreSimulator-1155.4+ (Xcode 27) ships the dtuhidd suppression machinery; older toolchains
    // have no `dtuhidd`, so skip the host probe entirely.
    guard shipsDTUHID(coreSimulatorVersion: coreSimulatorVersion) else {
      return false
    }
    return isDTUHIDDRunning()
  }

  /// The transport to use when a caller does not request one.
  static func defaultTransport(
    coreSimulatorVersion: String?,
    isDTUHIDDRunning: () -> Bool
  ) -> FBSimulatorHIDTransportType {
    let suppressed = isLegacyHIDSuppressed(
      coreSimulatorVersion: coreSimulatorVersion, isDTUHIDDRunning: isDTUHIDDRunning)
    return suppressed ? .dtuhid : .indigo
  }
}

// MARK: - Legacy HID suppression

extension FBSimulator {

  /// Whether an active `dtuhidd` has suppressed this simulator's legacy HID services.
  ///
  /// On Xcode 27 (CoreSimulator-1155.4) and later, the host-injected SimulatorHID disconnects the
  /// legacy `ExternalKeyboardService` while `dtuhidd` is active, so legacy keyboard events are
  /// delivered byte-correctly but produce no text (touch and the other services are unaffected). Read
  /// host-side — the authoritative guest notify state `com.apple.coredevice.dtuhidd.active` is not
  /// host-bridged — by locating `dtuhidd` in this simulator's `launchd_sim` process subtree.
  var isLegacyHIDSuppressed: Bool {
    FBSimulatorHIDTransportSelection.isLegacyHIDSuppressed(
      coreSimulatorVersion: FBSimulatorControlFrameworkLoader.loadedCoreSimulatorVersion,
      isDTUHIDDRunning: { self.isDTUHIDDRunning })
  }

  /// The HID transport to use when a caller does not request one: the DTUHID transport when an active
  /// `dtuhidd` has suppressed the legacy HID, and the legacy Indigo path otherwise. The selection
  /// criteria are deliberately the same as the suppression detection (`isLegacyHIDSuppressed`); this
  /// can be refined independently later if the two ever need to diverge.
  var defaultHIDTransport: FBSimulatorHIDTransportType {
    FBSimulatorHIDTransportSelection.defaultTransport(
      coreSimulatorVersion: FBSimulatorControlFrameworkLoader.loadedCoreSimulatorVersion,
      isDTUHIDDRunning: { self.isDTUHIDDRunning })
  }

  /// Whether a `dtuhidd` process is running in this simulator's `launchd_sim` subtree. `dtuhidd` runs
  /// as a child of the simulator's `launchd_sim`, so its presence in the process subtree is the
  /// per-simulator signal.
  private var isDTUHIDDRunning: Bool {
    FBProcessFetcher().simulatorSubprocess(named: "dtuhidd", forSimulatorUDID: udid) != nil
  }
}

// MARK: - Simulator process tree

private extension FBProcessFetcher {

  /// The host `launchd_sim` process backing the simulator with `udid`, matched by the UDID in its
  /// arguments, or `nil` if it cannot be found (e.g. the simulator is not booted).
  func launchdSim(forSimulatorUDID udid: String) -> FBProcessInfo? {
    processes(withProcessName: "launchd_sim").first { process in
      process.arguments.contains { $0.contains(udid) }
    }
  }

  /// The process identifier of a subprocess of the simulator's `launchd_sim` whose name contains
  /// `name`, or `nil` if there is none. A purely host-side query of the simulator's process subtree.
  func simulatorSubprocess(named name: String, forSimulatorUDID udid: String) -> pid_t? {
    guard let launchdSim = launchdSim(forSimulatorUDID: udid) else {
      return nil
    }
    let identifier = subprocess(of: launchdSim.processIdentifier, withName: name)
    return identifier > 0 ? identifier : nil
  }
}

// MARK: - Loaded CoreSimulator version

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
