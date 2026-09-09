/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

private struct BodyError: Error {}

@Suite
struct FBTemporaryDirectoryTests {

  private let temporaryDirectory = FBTemporaryDirectory(logger: FBControlCoreGlobalConfiguration.defaultLogger)

  private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  /// The directory exists for exactly the scope: created before the body sees it, deleted by the
  /// time the call returns — on the returning ending and the throwing one.
  @Test
  func withTemporaryDirectoryBody_DeletesTheDirectoryWhenTheBodyReturns() async throws {
    let handed = try await temporaryDirectory.withTemporaryDirectory { url -> URL in
      #expect(self.exists(url))
      return url
    }
    #expect(!exists(handed))
  }

  @Test
  func withTemporaryDirectoryBody_DeletesTheDirectoryWhenTheBodyThrows() async throws {
    nonisolated(unsafe) var handed: URL?
    await #expect(throws: BodyError.self) {
      try await self.temporaryDirectory.withTemporaryDirectory { url -> URL in
        handed = url
        throw BodyError()
      }
    }
    let url = try #require(handed)
    #expect(!exists(url))
  }

  /// The unscoped variant hands out a directory the caller owns: nothing deletes it behind the
  /// caller's back.
  @Test
  func temporaryDirectory_CreatesADirectoryTheCallerOwns() {
    let url = temporaryDirectory.temporaryDirectory()
    #expect(exists(url))
    temporaryDirectory.cleanOnExit()
    #expect(!exists(url))
  }

  /// The plain form of the subdirectory walk: the unique file inside each immediate subdirectory.
  @Test
  func filesInSubdirectoriesOf_ReturnsTheUniqueFileInEachSubdirectory() throws {
    let root = temporaryDirectory.temporaryDirectory()
    defer { temporaryDirectory.cleanOnExit() }
    for (subdir, file) in [("first", "a.txt"), ("second", "b.txt")] {
      let dir = root.appendingPathComponent(subdir)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try Data("payload".utf8).write(to: dir.appendingPathComponent(file))
    }
    let files = try temporaryDirectory.files(inSubdirectoriesOf: root)
    #expect((Set(files.map(\.lastPathComponent))) == (Set(["a.txt", "b.txt"])))
  }

}
