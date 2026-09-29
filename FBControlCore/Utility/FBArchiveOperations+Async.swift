/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension FBArchiveOperations {

  /// Async wrapper for `createGzipDataFromProcessInput:logger:`.
  public static func createGzipDataAsync(
    from input: FBProcessInput<AnyObject>,
    logger: any ControlCoreLogger
  ) async throws -> FBSubprocess<AnyObject, NSData, AnyObject> {
    return try await bridgeFBFuture(createGzipData(from: input, logger: logger))
  }

  /// Async wrapper for `createGzipForPath:logger:`.
  public static func createGzipAsync(
    forPath path: String,
    logger: any ControlCoreLogger
  ) async throws -> FBSubprocess<NSNull, InputStream, AnyObject> {
    return try await bridgeFBFuture(createGzip(forPath: path, logger: logger))
  }

  /// Async wrapper for `createGzippedTarForPath:logger:`.
  public static func createGzippedTarAsync(
    forPath path: String,
    logger: any ControlCoreLogger
  ) async throws -> FBSubprocess<NSNull, InputStream, AnyObject> {
    return try await bridgeFBFuture(createGzippedTar(forPath: path, logger: logger))
  }

  /// Async wrapper for `createGzippedTarDataForPath:queue:logger:`.
  public static func createGzippedTarDataAsync(
    forPath path: String,
    queue: DispatchQueue,
    logger: any ControlCoreLogger
  ) async throws -> Data {
    let value = try await bridgeFBFuture(
      createGzippedTarData(forPath: path, queue: queue, logger: logger))
    return value as Data
  }
}
