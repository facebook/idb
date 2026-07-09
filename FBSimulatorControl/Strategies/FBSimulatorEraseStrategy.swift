/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

@objc(FBSimulatorEraseStrategy)
public final class FBSimulatorEraseStrategy: NSObject {

  // MARK: - Public

  static func erase(_ simulator: FBSimulator) async throws {
    try await FBSimulatorShutdownStrategy.shutdownAsync(simulator)
    try await eraseContentsAndSettings(simulator)
  }

  // MARK: - Private

  private static func eraseContentsAndSettings(_ simulator: FBSimulator) async throws {
    // FBControlCoreLogger is a thread-safe ObjC protocol that is not Sendable.
    nonisolated(unsafe) let logger = simulator.logger
    let description = "\(simulator)"
    logger?.log("Erasing \(description)")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      simulator.device.eraseContentsAndSettingsAsync(withCompletionQueue: simulator.workQueue) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          logger?.log("Erased \(description)")
          continuation.resume(returning: ())
        }
      }
    }
  }
}
