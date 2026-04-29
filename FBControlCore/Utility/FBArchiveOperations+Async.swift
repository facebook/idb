/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension FBArchiveOperations {

  /// Async wrapper for `extractArchiveAtPath:toPath:overrideModificationTime:logger:`.
  public class func extractArchiveAsync(
    atPath path: String,
    toPath extractPath: String,
    overrideModificationTime overrideMTime: Bool,
    logger: any FBControlCoreLogger
  ) async throws -> String {
    let value = try await bridgeFBFuture(
      extractArchive(
        atPath: path,
        toPath: extractPath,
        overrideModificationTime: overrideMTime,
        logger: logger))
    return value as String
  }

  /// Async wrapper for `extractArchiveFromStream:toPath:overrideModificationTime:logger:compression:`.
  public class func extractArchiveAsync(
    fromStream stream: FBProcessInput<AnyObject>,
    toPath extractPath: String,
    overrideModificationTime overrideMTime: Bool,
    logger: any FBControlCoreLogger,
    compression: FBCompressionFormat
  ) async throws -> String {
    let value = try await bridgeFBFuture(
      extractArchive(
        fromStream: stream,
        toPath: extractPath,
        overrideModificationTime: overrideMTime,
        logger: logger,
        compression: compression))
    return value as String
  }

  /// Async wrapper for `extractGzipFromStream:toPath:logger:`.
  public class func extractGzipAsync(
    fromStream stream: FBProcessInput<AnyObject>,
    toPath extractPath: String,
    logger: any FBControlCoreLogger
  ) async throws -> String {
    let value = try await bridgeFBFuture(
      extractGzip(fromStream: stream, toPath: extractPath, logger: logger))
    return value as String
  }

  /// Async wrapper for `createGzipDataFromProcessInput:logger:`.
  public class func createGzipDataAsync(
    from input: FBProcessInput<AnyObject>,
    logger: any FBControlCoreLogger
  ) async throws -> FBSubprocess<AnyObject, NSData, AnyObject> {
    return try await bridgeFBFuture(createGzipData(from: input, logger: logger))
  }

  /// Async wrapper for `createGzipForPath:logger:`.
  public class func createGzipAsync(
    forPath path: String,
    logger: any FBControlCoreLogger
  ) async throws -> FBSubprocess<NSNull, InputStream, AnyObject> {
    return try await bridgeFBFuture(createGzip(forPath: path, logger: logger))
  }

  /// Async wrapper for `createGzippedTarForPath:logger:`.
  public class func createGzippedTarAsync(
    forPath path: String,
    logger: any FBControlCoreLogger
  ) async throws -> FBSubprocess<NSNull, InputStream, AnyObject> {
    return try await bridgeFBFuture(createGzippedTar(forPath: path, logger: logger))
  }

  /// Async wrapper for `createGzippedTarDataForPath:queue:logger:`.
  public class func createGzippedTarDataAsync(
    forPath path: String,
    queue: DispatchQueue,
    logger: any FBControlCoreLogger
  ) async throws -> Data {
    let value = try await bridgeFBFuture(
      createGzippedTarData(forPath: path, queue: queue, logger: logger))
    return value as Data
  }
}
