/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBProcessLogOperation)
public class FBProcessLogOperation: NSObject, FBLogOperation {

  // MARK: Properties

  @objc public let process: FBSubprocess<AnyObject, AnyObject, AnyObject>
  @objc public let consumer: any FBDataConsumer
  private let queue: DispatchQueue

  // MARK: Initializers

  @objc public init(process: FBSubprocess<AnyObject, AnyObject, AnyObject>, consumer: any FBDataConsumer, queue: DispatchQueue) {
    self.process = process
    self.consumer = consumer
    self.queue = queue
    super.init()
  }

  // MARK: FBiOSTargetOperation

  @objc public var completed: FBFuture<NSNull> {
    let process = self.process
    let result = process.exited(withCodes: Set([NSNumber(value: 0)]))
      .mapReplace(NSNull())
      .onQueue(queue, respondToCancellation: {
        return unsafeBitCast(process.sendSignal(SIGTERM, backingOffToKillWithTimeout: 5, logger: nil), to: FBFuture<NSNull>.self)
      })
    return unsafeBitCast(result, to: FBFuture<NSNull>.self)
  }

  // MARK: Class Methods

  @objc(osLogArgumentsInsertStreamIfNeeded:)
  public class func osLogArgumentsInsertStreamIfNeeded(_ arguments: [String]) -> [String] {
    guard let firstArgument = arguments.first else {
      return ["stream"]
    }
    if FBProcessLogOperation.osLogSubcommands.contains(firstArgument) {
      return arguments
    }
    return ["stream"] + arguments
  }

  // MARK: Private

  private static let osLogSubcommands: Set<String> = {
    return Set(["collect", "config", "erase", "show", "stream", "stats"])
  }()
}
