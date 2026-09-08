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
  /// time the call returns. `withFBFutureContext` awaits the teardown, so there is no window in
  /// which the deletion is still pending.
  @Test
  func withTemporaryDirectory_DeletesTheDirectoryWhenTheBodyReturns() async throws {
    let handed = try await withFBFutureContext(temporaryDirectory.withTemporaryDirectory()) { url -> URL in
      let url = url as URL
      #expect(self.exists(url))
      return url
    }
    #expect(!exists(handed))
  }

  /// The other ending: a throwing body propagates its error and the directory is deleted on the
  /// way out.
  @Test
  func withTemporaryDirectory_DeletesTheDirectoryWhenTheBodyThrows() async throws {
    nonisolated(unsafe) var handed: URL?
    await #expect(throws: BodyError.self) {
      try await withFBFutureContext(temporaryDirectory.withTemporaryDirectory()) { url -> URL in
        handed = url as URL
        throw BodyError()
      }
    }
    let url = try #require(handed)
    #expect(!exists(url))
  }

  /// The body-scoped variant carries the same two endings as the context form, without a context:
  /// the directory is gone by the time the call returns.
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

  /// Each immediate subdirectory of the extraction directory holds exactly one file, and those
  /// files are what come back, with the scoped directory deleted afterwards.
  @Test
  func filesFromSubdirs_ReturnsTheUniqueFileInEachSubdirectory() async throws {
    let root = temporaryDirectory.temporaryDirectory()
    defer { temporaryDirectory.cleanOnExit() }
    for (subdir, file) in [("first", "a.txt"), ("second", "b.txt")] {
      let dir = root.appendingPathComponent(subdir)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try Data("payload".utf8).write(to: dir.appendingPathComponent(file))
    }

    let context = FBFuture<NSURL>(result: root as NSURL)
      .onQueue(
        temporaryDirectory.queue,
        contextualTeardown: { (_: NSURL, _: FBFutureState) -> FBFuture<NSNull> in
          FBFuture<NSNull>.empty()
        })
    let files = try await withFBFutureContext(temporaryDirectory.files(fromSubdirs: context)) { files in
      (files as? [URL]) ?? []
    }
    #expect((Set(files.map(\.lastPathComponent))) == (Set(["a.txt", "b.txt"])))
  }
}
