/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Gets from "somewhere an application lives" to "an application bundle on
/// disk", reporting what it is doing as it goes.
///
/// This deliberately stops short of installing. Installing means different things
/// to different callers -- some persist the bundle alongside the target, some
/// codesign it first -- and all of them need the bundle rather than the installed
/// application.
public enum ApplicationArchive {

  /// Resolves `source` to a bundle and calls `perform` with it.
  ///
  /// The bundle is only valid for the duration of `perform`: anything unpacked is
  /// removed afterwards. Progress is reported as `Staging.withMaterialized` does.
  public static func withResolvedBundle<T>(
    from source: InstallSource,
    options: InstallOptions = InstallOptions(),
    totalStart: Date = Date(),
    downloadConfiguration: URLSessionConfiguration = .default,
    temporaryDirectory: TemporaryDirectory,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void = { _ in },
    perform: (BundleDescriptor) async throws -> T
  ) async throws -> T {
    try await Staging.withMaterialized(
      source, as: .application, options: options, totalStart: totalStart, downloadConfiguration: downloadConfiguration,
      temporaryDirectory: temporaryDirectory, logger: logger, onProgress: onProgress
    ) { tree in
      return try await perform(try Artifact.applicationBundle(in: tree, logger: logger))
    }
  }
}
