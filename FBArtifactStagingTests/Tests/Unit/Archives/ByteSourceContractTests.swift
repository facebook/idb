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

/// Raised by `FailingSource` once it has served its bytes, so a test can tell it apart from anything an extractor throws.
struct InjectedFailure: Error, CustomStringConvertible {
  var description: String { "injected upstream failure" }
}

/// Serves `data` up to `failingAt`, then throws `InjectedFailure` on every read: a producer that fails part way.
final class FailingSource: ByteSource {

  private let data: Data
  private let failingAt: Int
  private var offset = 0

  init(_ data: Data, failingAt: Int) {
    self.data = data
    self.failingAt = min(failingAt, data.count)
  }

  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    guard offset < failingAt else {
      throw InjectedFailure()
    }
    let count = min(buffer.count, failingAt - offset)
    data.copyBytes(to: buffer.bindMemory(to: UInt8.self), from: offset..<offset + count)
    offset += count
    return count
  }
}

/// Counts what is read from the source it wraps, so a test can see whether a decorator reached the end of its input.
final class CountingSource: ByteSource {

  private let source: any ByteSource
  private(set) var bytesRead = 0
  private(set) var reachedEnd = false

  init(_ source: any ByteSource) {
    self.source = source
  }

  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    let count = try source.read(into: buffer)
    bytesRead += count
    reachedEnd = reachedEnd || count == 0
    return count
  }
}

/// The contract every `ByteSource` keeps, whatever it decorates or reads from:
///
/// - `read(into:)` returns the input's bytes in order, then 0 at the end and on every read after it.
/// - `drain()` reads to the end of the underlying input, discarding it, so that a writer is never left blocked. Extractors
///   call it when they *succeed*, so it is not a way to cancel.
/// - An error from the underlying input is rethrown as it is, never replaced by an end of input.
@Suite
struct ByteSourceContractTests {

  /// A source over some bytes, and what it reads as.
  struct Subject: CustomTestStringConvertible, Sendable {
    let name: String
    /// Builds a source that reads as `expected` over `underlying`, which the source must read to its end.
    let make: @Sendable (_ underlying: any ByteSource) throws -> any ByteSource
    /// How the plain bytes are encoded for this source to read them back.
    let encode: @Sendable (Data) throws -> Data

    var testDescription: String { name }
  }

  static let payload = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761 >> 13) })

  static let subjects: [Subject] = [
    Subject(name: "PeekableSource", make: { PeekableSource($0) }, encode: { $0 }),
    Subject(
      name: "PeekableSource peeked first",
      make: { source in
        let peekable = PeekableSource(source)
        _ = try peekable.peek(ArchiveFormat.sniffLength)
        return peekable
      }, encode: { $0 }),
    Subject(name: "GzipSource", make: { try GzipSource($0) }, encode: { try GzippingSource(DataSource($0)).readAll() }),
    Subject(name: "ZstdSource", make: { try ZstdSource($0) }, encode: { ZstdFrame.stored($0) }),
    Subject(name: "ZstdSource.ifZstd over zstd", make: { try ZstdSource.ifZstd($0) }, encode: { ZstdFrame.stored($0) }),
    Subject(name: "ZstdSource.ifZstd over plain", make: { try ZstdSource.ifZstd($0) }, encode: { $0 }),
    Subject(name: "GzippingSource then GzipSource", make: { try GzipSource(GzippingSource($0)) }, encode: { $0 }),
  ]

  static let bufferSizes = [1, 7, 4096, 1 << 16]

  // MARK: - Reading

  @Test(arguments: subjects, bufferSizes)
  func readsTheInputInOrderThenEndsForGood(_ subject: Subject, bufferSize: Int) throws {
    let source = try subject.make(DataSource(try subject.encode(Self.payload), pieceSize: 1000))
    var contents = Data()
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while case let count = try buffer.withUnsafeMutableBytes({ try source.read(into: $0) }), count > 0 {
      contents.append(contentsOf: buffer[..<count])
    }
    #expect(contents == Self.payload)
    #expect(try buffer.withUnsafeMutableBytes { try source.read(into: $0) } == 0)
    #expect(try buffer.withUnsafeMutableBytes { try source.read(into: $0) } == 0)
  }

  @Test
  func aFileDescriptorReadsAPipeToItsEnd() throws {
    var descriptors: [Int32] = [0, 0]
    #expect(pipe(&descriptors) == 0)
    let writeEnd = descriptors[1]
    let writer = Thread {
      Self.payload.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
          offset += max(0, write(writeEnd, bytes.baseAddress! + offset, min(4096, bytes.count - offset)))
        }
      }
      close(writeEnd)
    }
    writer.start()
    defer { close(descriptors[0]) }
    #expect(try FileDescriptorSource(descriptors[0]).readAll() == Self.payload)
  }

  @Test
  func aClosedFileDescriptorThrowsRatherThanEnding() {
    #expect(throws: POSIXError.self) {
      _ = try FileDescriptorSource(-1).readAll()
    }
  }

  @Test
  func aPipeReadsWhatWasWrittenThenEnds() async throws {
    let contents = try await BytePipe(Self.payload).reading { source in try source.readAll() }
    #expect(contents == Self.payload)
  }

  // MARK: - Draining

  @Test(arguments: subjects)
  func drainingReadsTheUnderlyingInputToItsEnd(_ subject: Subject) throws {
    let underlying = CountingSource(DataSource(try subject.encode(Self.payload), pieceSize: 1000))
    let source = try subject.make(underlying)
    var buffer = [UInt8](repeating: 0, count: 100)
    _ = try buffer.withUnsafeMutableBytes { try source.read(into: $0) }
    try source.drain()
    #expect(underlying.reachedEnd)
    #expect(try buffer.withUnsafeMutableBytes { try source.read(into: $0) } == 0)
  }

  // MARK: - Errors

  @Test(arguments: subjects, [0, 10, 150_000])
  func anUnderlyingFailureIsRethrownNotTakenForTheEnd(_ subject: Subject, failingAt plainOffset: Int) throws {
    let encoded = try subject.encode(Self.payload)
    // The offset is into the plain payload; scaled into the encoding, which only ever shrinks or slightly grows it.
    let offset = plainOffset * encoded.count / Self.payload.count
    #expect(throws: InjectedFailure.self) {
      let source = try subject.make(FailingSource(encoded, failingAt: offset))
      _ = try source.readAll()
    }
  }

  @Test(arguments: subjects)
  func drainingRethrowsAnUnderlyingFailure(_ subject: Subject) throws {
    let encoded = try subject.encode(Self.payload)
    #expect(throws: InjectedFailure.self) {
      let source = try subject.make(FailingSource(encoded, failingAt: encoded.count / 2))
      try source.drain()
    }
  }
}
