/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
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
    onReport: @escaping @Sendable (StagingReport) -> Void = { _ in },
    perform: (BundleDescriptor) async throws -> T
  ) async throws -> T {
    try await Staging.withMaterialized(
      source, as: .application, options: options, totalStart: totalStart, downloadConfiguration: downloadConfiguration,
      temporaryDirectory: temporaryDirectory, logger: logger, onProgress: onProgress,
      onReport: onReport
    ) { tree in
      return try await perform(try Artifact.applicationBundle(in: tree, logger: logger))
    }
  }
}

extension ApplicationCommands {

  /// Installs the application `source` holds, unpacking it first if it is an archive, and reports each stage through
  /// `onProgress` as `Staging.install` does.
  ///
  /// The target installs from wherever staging left the bundle. A caller that keeps the bundle afterwards, or signs it
  /// first, stages it with `Staging.install` instead.
  public func install(
    from source: InstallSource,
    options: InstallOptions = InstallOptions(),
    totalStart: Date = Date(),
    downloadConfiguration: URLSessionConfiguration = .default,
    temporaryDirectory: TemporaryDirectory,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void = { _ in },
    onReport: @escaping @Sendable (StagingReport) -> Void = { _ in }
  ) async throws -> InstalledApplication {
    try await Staging.install(
      source, as: .application, options: options, totalStart: totalStart, downloadConfiguration: downloadConfiguration,
      temporaryDirectory: temporaryDirectory, logger: logger, onProgress: onProgress, onReport: onReport,
      name: \.bundle.identifier
    ) { artifact, _ in
      try await install(atPath: artifact.url.path)
    }
  }
}
