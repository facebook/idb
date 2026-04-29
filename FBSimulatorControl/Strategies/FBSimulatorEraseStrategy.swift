/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

@objc(FBSimulatorEraseStrategy)
public final class FBSimulatorEraseStrategy: NSObject {

  // MARK: - Public

  @objc
  public class func erase(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    fbFutureFromAsync {
      try await eraseAsync(simulator)
      return NSNull()
    }
  }

  // MARK: - Async

  static func eraseAsync(_ simulator: FBSimulator) async throws {
    try await FBSimulatorShutdownStrategy.shutdownAsync(simulator)
    try await eraseContentsAndSettingsAsync(simulator)
  }

  // MARK: - Private

  private static func eraseContentsAndSettingsAsync(_ simulator: FBSimulator) async throws {
    let logger = simulator.logger
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
