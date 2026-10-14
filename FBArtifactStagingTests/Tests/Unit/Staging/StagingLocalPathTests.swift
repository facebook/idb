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

    let installed = await #expect(throws: InstallError.self) {
      try await Staging.install(
        .localPath(dylib.path), as: .dylib(name: "libSample.dylib"),
        temporaryDirectory: TemporaryDirectory(rootDirectory: root.appendingPathComponent("staging"), logger: logger), logger: logger
      ) { _, _ in
        Issue.record("an unreadable file reached the install")
        return Staged()
      }
    }

    guard case .unidentifiable(_, let underlying)? = installed else {
      Issue.record("Expected the file to be unidentifiable, got \(String(describing: installed))")
      return
    }
    #expect((underlying as? CocoaError)?.code == .fileReadNoPermission, "\(underlying)")
  }
}
