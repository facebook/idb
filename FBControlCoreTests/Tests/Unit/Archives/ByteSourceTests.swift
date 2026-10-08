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

@Suite
struct ByteSourceTests {

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()

  private func gzip(_ data: Data) throws -> Data {
    let input = root.appendingPathComponent(UUID().uuidString)
    try data.write(to: input)
    let process = try Process.run(URL(fileURLWithPath: "/usr/bin/gzip"), arguments: ["-nf", input.path])
    process.waitUntilExit()
    return try Data(contentsOf: input.appendingPathExtension("gz"))
  }

  @Test
  func whatIsPeekedIsStillRead() throws {
    let source = PeekableSource(DataSource(Data("abcdef".utf8), pieceSize: 1))

    #expect(try source.peek(3) == Data("abc".utf8))
    #expect(try source.readAll() == Data("abcdef".utf8))
  }

  @Test
  func aPeekPastTheEndIsShort() throws {
    #expect(try PeekableSource(DataSource(Data("ab".utf8))).peek(4) == Data("ab".utf8))
  }

  @Test
  func gzipMembersAreReadOneAfterAnother() throws {
    let contents = try gzip(Data("first ".utf8)) + gzip(Data("second".utf8))

    #expect(try GzipSource(DataSource(contents, pieceSize: 7)).readAll() == Data("first second".utf8))
  }

  @Test
  func anythingAfterAGzipMemberIsIgnored() throws {
    let contents = try gzip(Data("member".utf8)) + Data("trailing".utf8)

    #expect(try GzipSource(DataSource(contents)).readAll() == Data("member".utf8))
  }

  @Test
  func aTruncatedGzipIsCorrupt() throws {
    let contents = try gzip(Data(String(repeating: "x", count: 10_000).utf8))

    #expect(throws: ArchiveError.corrupt("the gzip ends early")) {
      try GzipSource(DataSource(contents.prefix(contents.count / 2))).readAll()
    }
  }

  @Test
  func drainingAGzipDoesNotInflateIt() throws {
    var corrupt = try gzip(Data(String(repeating: "x", count: 10_000).utf8))
    corrupt[corrupt.count / 2] ^= 0xFF
    let raw = DataSource(corrupt, pieceSize: 100)

    try GzipSource(raw).drain()

    #expect(try raw.readAll().isEmpty)
  }

  @Test
  func whatATeeReadsReachesItsFileAndDrainingReadsTheRest() throws {
    let contents = Data("everything read".utf8)
    let path = root.appendingPathComponent("tee").path
    #expect(FileManager.default.createFile(atPath: path, contents: nil))
    let file = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    let source = TeeSource(DataSource(contents, pieceSize: 3), to: file)
    var buffer = [UInt8](repeating: 0, count: 4)

    #expect(try buffer.withUnsafeMutableBytes { try source.read(into: $0) } == 3)
    try source.drain()
    try file.close()

    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == contents)
  }
}
