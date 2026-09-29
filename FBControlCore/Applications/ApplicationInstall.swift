/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension ApplicationCommands {

  /// Installs from any source, reporting progress through a callback.
  ///
  /// The install stage covers only handing the bundle to the target. Fetching,
  /// unpacking and finding the bundle are reported by the stages before it, so a
  /// source that is already a `.app` reports this stage and no other.
  public func install(
    from source: InstallSource,
    options: InstallOptions = InstallOptions(),
    downloadConfiguration: URLSessionConfiguration = .default,
    temporaryDirectory: TemporaryDirectory,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void = { _ in }
  ) async throws -> InstalledApplication {
    let totalStart = Date()
    return try await ApplicationArchive.withResolvedBundle(
      from: source,
      options: options,
      totalStart: totalStart,
      downloadConfiguration: downloadConfiguration,
      temporaryDirectory: temporaryDirectory,
      logger: logger,
      onProgress: onProgress
    ) { bundle in
      let stageStart = Date()
      onProgress(.installStarted(timing: .measure(stageStart: stageStart, totalStart: totalStart), appPath: bundle.path))
      let installed = try await install(atPath: bundle.path)
      onProgress(
        .installCompleted(
          timing: .measure(stageStart: stageStart, totalStart: totalStart),
          appPath: bundle.path,
          bundleId: installed.bundle.identifier))
      return installed
    }
  }
}
