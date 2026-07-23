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

struct FBSimulatorHIDBootIdentity: Equatable, Sendable {
  enum Generation: Equatable, Sendable {
    case coreSimulatorLastBootedAt(Date)
    case launchdProcess(processIdentifier: pid_t, startTimeMicroseconds: UInt64)
  }

  let generation: Generation
}

enum FBSimulatorHIDBootIdentityResolver {
  static func identity(for simulator: FBSimulator) throws -> FBSimulatorHIDBootIdentity {
    let identity = identity(lastBootedAt: lastBootedAt(of: simulator.device)) {
      let matchingProcesses = FBProcessFetcher()
        .processes(withProcessName: "launchd_sim")
        .filter { process in
          process.arguments.contains { $0.contains(simulator.udid) }
        }
        .compactMap(identity(for:))

      return matchingProcesses.max(by: {
        guard
          case let .launchdProcess(lhsPID, lhsStartTime) = $0.generation,
          case let .launchdProcess(rhsPID, rhsStartTime) = $1.generation
        else {
          return false
        }
        if lhsStartTime == rhsStartTime {
          return lhsPID < rhsPID
        }
        return lhsStartTime < rhsStartTime
      })
    }
    guard let identity else {
      throw FBSimulatorError
        .describe("Could not resolve the launchd_sim boot identity for simulator \(simulator.udid)")
        .build()
    }
    return identity
  }

  /// Reads the private `SimDevice.lastBootedAt` only after confirming the runtime object still
  /// implements the getter. The property comes from a reverse-engineered header
  /// (`PrivateHeaders/CoreSimulator/SimDevice.h`), so a future CoreSimulator could remove or rename
  /// it; an unguarded read would then be an unrecognized-selector crash — one that would also stop
  /// the launchd_sim/proc_pidinfo fallback from ever engaging. Returning nil routes to that fallback.
  /// Takes `NSObject` (not `SimDevice`) so the guard is exercisable in unit tests with plain doubles.
  static func lastBootedAt(of device: NSObject) -> Date? {
    let selector = #selector(getter: SimDevice.lastBootedAt)
    guard device.responds(to: selector) else {
      return nil
    }
    return device.perform(selector)?.takeUnretainedValue() as? Date
  }

  static func identity(
    lastBootedAt: Date?,
    fallback: () throws -> FBSimulatorHIDBootIdentity?
  ) rethrows -> FBSimulatorHIDBootIdentity? {
    if let lastBootedAt {
      return FBSimulatorHIDBootIdentity(
        generation: .coreSimulatorLastBootedAt(lastBootedAt)
      )
    }
    return try fallback()
  }

  static func identity(for process: FBProcessInfo) -> FBSimulatorHIDBootIdentity? {
    var processInfo = proc_bsdinfo()
    let expectedSize = MemoryLayout<proc_bsdinfo>.size
    let copiedSize = proc_pidinfo(
      process.processIdentifier,
      PROC_PIDTBSDINFO,
      0,
      &processInfo,
      Int32(expectedSize)
    )
    guard copiedSize == Int32(expectedSize) else {
      return nil
    }
    let microseconds = UInt64(processInfo.pbi_start_tvsec) * 1_000_000
      + UInt64(processInfo.pbi_start_tvusec)
    return FBSimulatorHIDBootIdentity(
      generation: .launchdProcess(
        processIdentifier: process.processIdentifier,
        startTimeMicroseconds: microseconds
      )
    )
  }
}
