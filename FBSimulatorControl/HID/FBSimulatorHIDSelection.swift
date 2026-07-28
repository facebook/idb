/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import CoreSimulator
import Darwin
@preconcurrency import FBControlCore
import Foundation

// MARK: - Legacy HID suppression

extension FBSimulator {

  /// Whether an active `dtuhidd` has suppressed this simulator's legacy HID services.
  ///
  /// On Xcode 27 (CoreSimulator-1155.4) and later, the host-injected SimulatorHID disconnects the
  /// legacy HID services while `dtuhidd` is active, so Indigo events are delivered byte-correctly
  /// but produce no guest input. Probe the simulator's DTUHID bootstrap service instead of walking
  /// the host process tree: process enumeration is unavailable to sandboxed clients such as
  /// RocketSim, while `SimDevice.lookup` is both per-simulator and sandbox-safe.
  var isLegacyHIDSuppressed: Bool {
    FBSimulatorHIDTransportSelection.isLegacyHIDSuppressed(
      coreSimulatorVersion: FBSimulatorControlFrameworkLoader.loadedCoreSimulatorVersion,
      servicePort: {
        var lookupError: NSError?
        return device.lookup(FBSimulatorDTUHIDTransport.digitizerServiceName, error: &lookupError)
      },
      deallocate: { port in
        mach_port_deallocate(mach_task_self_, port)
      }
    )
  }

  /// The HID transport to use when a caller does not request one: the DTUHID transport when an active
  /// `dtuhidd` has suppressed the legacy HID, and the legacy Indigo path otherwise. The selection
  /// criteria are deliberately the same as the suppression detection (`isLegacyHIDSuppressed`); this
  /// can be refined independently later if the two ever need to diverge.
  var defaultHIDTransport: FBSimulatorHIDTransportType {
    isLegacyHIDSuppressed ? .dtuhid : .indigo
  }
}

enum FBSimulatorHIDTransportSelection {

  static func isLegacyHIDSuppressed(
    coreSimulatorVersion: String?,
    servicePort: () -> mach_port_t,
    deallocate: (mach_port_t) -> Void
  ) -> Bool {
    guard let coreSimulatorVersion,
      coreSimulatorVersion.compare("1155.4", options: .numeric) != .orderedAscending
    else {
      return false
    }

    let port = servicePort()
    guard port != MACH_PORT_NULL else {
      return false
    }
    deallocate(port)
    return true
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
