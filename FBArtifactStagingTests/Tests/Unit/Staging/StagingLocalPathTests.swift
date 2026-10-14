/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBArtifactStaging
@testable import FBControlCore
import Foundation
import Testing

/// What staging does with a local path it can't read.
@Suite
struct StagingLocalPathTests {

  private struct Staged: InstalledName {
    var installedName: String { "staged" }
  }

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let logger = ControlCoreGlobalConfiguration.defaultLogger

  @Test
  func anUnreadableDylibIsNotInstalled() async throws {
    let dylib = root.appendingPathComponent("libSample.dylib")
    try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: dylib)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dylib.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dylib.path) }
    try #require(FileHandle(forReadingAtPath: dylib.path) == nil, "the file is still readable, as it is to root")

    let installed = try await Staging.install(
      .localPath(dylib.path), as: .dylib(name: "libSample.dylib"),
      temporaryDirectory: TemporaryDirectory(rootDirectory: root.appendingPathComponent("staging"), logger: logger), logger: logger
    ) { artifact, inPlace in
      #expect(inPlace)
      return Staged()
    }

    // BUG: a file staging can't read is handed to the install as the artifact in place, so the install fails later on
    // whatever reads it next — flipped in the following commit.
    #expect(installed.installedName == "staged")
  }
}
