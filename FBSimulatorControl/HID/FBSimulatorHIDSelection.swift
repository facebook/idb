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
    // Only CoreSimulator-1155.4+ (Xcode 27) ships the dtuhidd suppression machinery; older toolchains
    // have no `dtuhidd`, so skip the process-tree walk entirely.
    guard let version = FBSimulatorControlFrameworkLoader.loadedCoreSimulatorVersion,
      version.compare("1155.4", options: .numeric) != .orderedAscending
    else {
      return false
    }
    // `dtuhidd` runs as a child of the simulator's `launchd_sim`; its presence in the process subtree
    // is the per-simulator signal.
    return FBProcessFetcher().simulatorSubprocess(named: "dtuhidd", forSimulatorUDID: udid) != nil
  }

  /// The HID transport to use when a caller does not request one: the DTUHID transport when an active
  /// `dtuhidd` has suppressed the legacy HID, and the legacy Indigo path otherwise. The selection
  /// criteria are deliberately the same as the suppression detection (`isLegacyHIDSuppressed`); this
  /// can be refined independently later if the two ever need to diverge.
  var defaultHIDTransport: FBSimulatorHIDTransportType {
    isLegacyHIDSuppressed ? .dtuhid : .indigo
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
