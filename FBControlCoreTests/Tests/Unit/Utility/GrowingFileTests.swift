/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing
import os

@Suite
struct GrowingFileTests {

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()

  private func copied(from path: String, isComplete: () -> Bool) async throws -> Data {
    let output = OutputStream.toMemory()
    output.open()
    defer { output.close() }
    try await GrowingFile.copy(from: path, to: output, isComplete: isComplete)
    return try #require(output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)
  }

  @Test
  func copy_FollowsWritesUntilComplete() async throws {
    let path = root.appendingPathComponent("growing").path
    FileManager.default.createFile(atPath: path, contents: nil)
    let chunks = (0..<5).map { Data(repeating: UInt8($0), count: 300_000) }
    let complete = OSAllocatedUnfairLock(initialState: false)
    let writer = Task {
      let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
      defer { try? handle.close() }
      for chunk in chunks {
        try handle.write(contentsOf: chunk)
        try await Task.sleep(nanoseconds: 20_000_000)
      }
      complete.withLock { $0 = true }
    }

    let data = try await copied(from: path) { complete.withLock { $0 } }

    try await writer.value
    #expect(data == chunks.reduce(Data(), +))
  }

  @Test
  func copy_OfACompleteFile_CopiesItAll() async throws {
    let path = root.appendingPathComponent("complete").path
    let contents = Data(repeating: 7, count: 3 << 20)
    FileManager.default.createFile(atPath: path, contents: contents)

    let data = try await copied(from: path) { true }

    #expect(data == contents)
  }
}
