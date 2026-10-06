/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Decompresses a zstd stream to a file as it arrives.
public enum ZstdStreamDecompressor {

  /// Writes what `input` decompresses to into the file at `path`, and the same
  /// to `tee` for as long as `tee` accepts it: the file is complete either way.
  public static func decompress(
    _ input: FBProcessInput<AnyObject>,
    toPath path: String,
    teeingTo tee: OutputStream,
    logger: any ControlCoreLogger
  ) async throws {
    let file = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    let fileDescriptor = try await bridgeFBFuture(input.attach()).fileDescriptor
    let result = await offCooperativePool {
      let compressed = FileDescriptorSource(fileDescriptor)
      do {
        try copy(try ZstdSource(compressed), to: file, teeingTo: tee, logger: logger)
      } catch {
        // Leaves nothing writing to the input blocked on it.
        try? compressed.drain()
        throw error
      }
    }
    _ = try? await bridgeFBFuture(input.detach())
    let closed = Result { try file.close() }
    try result.get()
    try closed.get()
  }

  private static func copy(_ source: any ByteSource, to file: FileHandle, teeingTo output: OutputStream, logger: any ControlCoreLogger) throws {
    var tee: OutputStream? = output
    tee?.open()
    defer { tee?.close() }
    var chunk = [UInt8](repeating: 0, count: 1 << 16)
    while true {
      let count = try chunk.withUnsafeMutableBytes { try source.read(into: $0) }
      guard count > 0 else {
        return
      }
      let data = Data(chunk[..<count])
      try file.write(contentsOf: data)
      guard let stream = tee else {
        continue
      }
      do {
        try stream.writeAll(data)
      } catch {
        // The reader may finish before the end or fail; the file carries on regardless.
        logger.log("Stopped teeing the decompressed stream, which carries on to the file: \(error)")
        stream.close()
        tee = nil
      }
    }
  }
}
