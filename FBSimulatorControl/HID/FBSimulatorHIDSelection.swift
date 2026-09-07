/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

// MARK: - Transport selection policy

/// Decides which HID transport a caller that did not request one gets, and whether the legacy Indigo
/// keyboard path is functional.
///
/// Deliberately not a probe of whether `dtuhidd` is *resident*: it is a demand-launched,
/// pressured-exit job, so it is normally not running even on a simulator that routes all HID through
/// it. This decides only what to *prefer*; whether `dtuhidd` can actually be reached is settled where
/// it is observable, by `FBSimulatorDTUHIDTransport.dtuhid(for:)` looking the service up.
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

  /// Whether the guest has handed its legacy keyboard service over to `dtuhidd`.
  ///
  /// A property of the CoreSimulator version alone: from 1155.4 the handover happens for the lifetime
  /// of the boot, whether or not the daemon is resident at the moment it is asked.
  static func isLegacyKeyboardSuppressed(coreSimulatorVersion: String?) -> Bool {
    shipsDTUHID(coreSimulatorVersion: coreSimulatorVersion)
  }

  /// The transport to prefer when a caller does not request one. The toolchain is the only condition;
  /// every product family, Apple TV included, can be driven over DTUHID.
  static func defaultTransport(coreSimulatorVersion: String?) -> FBSimulatorHIDTransportType {
    guard shipsDTUHID(coreSimulatorVersion: coreSimulatorVersion) else {
      return .indigo
    }
    return .dtuhid
  }
}

// MARK: - Legacy keyboard suppression

extension FBSimulator {

  /// Whether this simulator's guest has handed its legacy keyboard service over to `dtuhidd`.
  ///
  /// On Xcode 27 (CoreSimulator-1155.4) and later Indigo keyboard events are delivered byte-correctly
  /// and then dropped. Indigo button events remain functional. The authoritative guest notify state
  /// `com.apple.coredevice.dtuhidd.active` is not host-bridged, so this follows the CoreSimulator
  /// version rather than trying to observe the guest.
  var isLegacyKeyboardSuppressed: Bool {
    FBSimulatorHIDTransportSelection.isLegacyKeyboardSuppressed(
      coreSimulatorVersion: FBSimulatorControlFrameworkLoader.loadedCoreSimulatorVersion)
  }

  /// The HID transport to prefer when a caller does not request one: DTUHID once the toolchain ships
  /// `dtuhidd`, the legacy Indigo path otherwise. A preference, not a guarantee — `FBSimulatorHID`
  /// falls back to Indigo if `dtuhidd` turns out to be unreachable.
  var defaultHIDTransport: FBSimulatorHIDTransportType {
    FBSimulatorHIDTransportSelection.defaultTransport(
      coreSimulatorVersion: FBSimulatorControlFrameworkLoader.loadedCoreSimulatorVersion)
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
