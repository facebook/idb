/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension FBInstrumentsOperation {

  /// Async wrapper for `operationWithTarget:configuration:logger:`.
  public class func operationAsync(
    target: any FBiOSTarget,
    configuration: FBInstrumentsConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBInstrumentsOperation {
    return try await bridgeFBFuture(operation(with: target, configuration: configuration, logger: logger))
  }

  /// Async wrapper for `-stop`. Returns the trace file URL.
  public func stopAsync() async throws -> URL {
    return try await bridgeFBFuture(stop()) as URL
  }

  /// Async wrapper for `postProcess:traceFile:queue:logger:`. Returns the post-processed trace URL.
  public class func postProcessAsync(
    arguments: [String]?,
    traceFile: URL,
    queue: DispatchQueue,
    logger: (any FBControlCoreLogger)?
  ) async throws -> URL {
    return try await bridgeFBFuture(postProcess(arguments, traceFile: traceFile, queue: queue, logger: logger)) as URL
  }
}
