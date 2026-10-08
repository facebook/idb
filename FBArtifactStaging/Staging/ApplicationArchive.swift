/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

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
