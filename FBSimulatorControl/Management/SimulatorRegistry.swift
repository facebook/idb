/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Foundation

/// Vends at most one live `Simulator` per simulator UDID in the process.
///
/// State hangs off a `Simulator` — its `commandCache`, HID connection and temporary directory — so
/// two instances wrapping the same device would split it. Entries are held weakly: while anything
/// holds a `Simulator`, every request for its device returns it; once nothing does, the next
/// request builds a fresh one. UDIDs are unique across device sets, so the key holds even when
/// the same device is reached through different `SimDeviceSet` instances.
final class SimulatorRegistry: @unchecked Sendable {

  static let shared = SimulatorRegistry()

  // Guards `simulators`, so that two callers racing for the same device build only one instance.
  private let lock = NSLock()
  private let simulators = NSMapTable<NSString, Simulator>.strongToWeakObjects()

  /// Returns the live `Simulator` for `device`, calling `make` to build one only when none is live.
  func simulator(for device: SimDevice, make: (SimDevice) -> Simulator) -> Simulator {
    let key = device.udid.uuidString as NSString
    lock.lock()
    defer { lock.unlock() }
    if let existing = simulators.object(forKey: key) {
      return existing
    }
    let simulator = make(device)
    simulators.setObject(simulator, forKey: key)
    return simulator
  }
}
