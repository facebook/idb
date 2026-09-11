/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public final class ProcessLogOperation: LogOperation {

  public let process: FBSubprocess<AnyObject, AnyObject, AnyObject>
  public let consumer: any FBDataConsumer
  private let queue: DispatchQueue

  public init(process: FBSubprocess<AnyObject, AnyObject, AnyObject>, consumer: any FBDataConsumer, queue: DispatchQueue) {
    self.process = process
    self.consumer = consumer
    self.queue = queue
  }

  // MARK: - LogOperation

  public var completed: FBFuture<NSNull> {
    let process = self.process
    let result = process.exited(withCodes: Set([NSNumber(value: 0)]))
      .mapReplace(NSNull())
      .onQueue(
        queue,
        respondToCancellation: {
          process.sendSignal(SIGTERM, backingOffToKillWithTimeout: 5, logger: nil).retyped(FBFuture<NSNull>.self)
        })
    return result.retyped(FBFuture<NSNull>.self)
  }

  public func waitUntilCompleted() async throws {
    try await bridgeFBFutureVoid(completed)
  }

  public class func osLogArgumentsInsertStreamIfNeeded(_ arguments: [String]) -> [String] {
    guard let firstArgument = arguments.first else {
      return ["stream"]
    }
    if ProcessLogOperation.osLogSubcommands.contains(firstArgument) {
      return arguments
    }
    return ["stream"] + arguments
  }

  private static let osLogSubcommands: Set<String> = {
    Set(["collect", "config", "erase", "show", "stream", "stats"])
  }()
}
