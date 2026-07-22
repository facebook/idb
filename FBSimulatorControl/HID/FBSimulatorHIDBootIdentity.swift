/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@preconcurrency import FBControlCore
import Foundation

struct FBSimulatorHIDBootIdentity: Equatable, Sendable {
  let processIdentifier: pid_t
  let startTimeMicroseconds: UInt64
}

enum FBSimulatorHIDBootIdentityResolver {
  static func identity(for simulator: FBSimulator) throws -> FBSimulatorHIDBootIdentity {
    let matchingProcesses = FBProcessFetcher()
      .processes(withProcessName: "launchd_sim")
      .filter { process in
        process.arguments.contains { $0.contains(simulator.udid) }
      }
      .compactMap(identity(for:))

    guard let identity = matchingProcesses.max(by: {
      if $0.startTimeMicroseconds == $1.startTimeMicroseconds {
        return $0.processIdentifier < $1.processIdentifier
      }
      return $0.startTimeMicroseconds < $1.startTimeMicroseconds
    }) else {
      throw FBSimulatorError
        .describe("Could not resolve the launchd_sim boot identity for simulator \(simulator.udid)")
        .build()
    }
    return identity
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
      processIdentifier: process.processIdentifier,
      startTimeMicroseconds: microseconds
    )
  }
}
