/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import zlib

/// Extracts a zip read forwards as it arrives, from each entry's local header,
/// decoding on the calling thread and writing several files at once.
///
/// Like `bsdtar` reading a pipe, it cannot know what only the central directory
/// at the end records: every entry is written as a regular file or directory
/// with the default mode, and `._` files are kept.
/// `ZipCentralDirectory.repair(extractedAt:)` applies the rest once the whole zip
/// is at hand.
public enum ZipStreamExtractor {

  @discardableResult
  public static func extract(from fileDescriptor: Int32, to root: String, overrideModificationTime: Bool = false) throws -> ZipExtractor.Summary {
    var reader = Reader(fileDescriptor: fileDescriptor)
    let writer = ParallelFileWriter(overrideModificationTime: overrideModificationTime)
    var directories: [(path: String, modified: Date?)] = []
    var summary = ZipExtractor.Summary(files: 0, bytes: 0)
    do {
      var created: Set<String> = []
      func createDirectories(_ relative: String) throws {
        guard !relative.isEmpty, !created.contains(relative) else {
          return
        }
        try createDirectories((relative as NSString).deletingLastPathComponent)
        try ZipExtractor.makeDirectory((root as NSString).appendingPathComponent(relative))
        created.insert(relative)
      }
      while let header = try LocalHeader(reading: &reader) {
        let relative = try ZipCentralDirectory.safeRelativePath(header.path)
        if header.path.hasSuffix("/") {
          try reader.decode(header) { _ in }
          if !relative.isEmpty {
            try createDirectories(relative)
            directories.append(((root as NSString).appendingPathComponent(relative), header.modified))
          }
          continue
        }
        if relative == "__MACOSX" || relative.hasPrefix("__MACOSX/") {
          try reader.decode(header) { _ in }
          continue
        }
        try createDirectories((relative as NSString).deletingLastPathComponent)
        var size: UInt64 = 0
        try writer.write((root as NSString).appendingPathComponent(relative), modified: header.modified.map { timespec(tv_sec: Int(floor($0.timeIntervalSince1970)), tv_nsec: 0) }) {
          size = try reader.decode(header, into: $0)
        }
        summary.files += 1
        summary.bytes += size
      }
      try reader.drain()
    } catch {
      writer.fail(error)
      // Closing the pipe early would fail the writer, or raise SIGPIPE in it; the
      // fallback extracts the spooled copy, which is only complete at the end anyway.
      try? reader.drain()
    }
    try writer.finish()
    if !overrideModificationTime {
      for (path, modified) in directories.reversed() {
        if let modified {
          try ZipExtractor.setTimes(modified) { utimes(path, $0) }
        }
      }
    }
    return summary
  }

  // MARK: - Private

  private struct LocalHeader {
    var path: String
    var flags: UInt16
    var method: UInt16
    var crc32: UInt32
    var compressedSize: UInt64
    var size: UInt64
    var zip64 = false
    var modified: Date?

    /// Nil at the central directory, which follows the last entry.
    init?(reading reader: inout Reader) throws {
      guard let signature = try reader.peekSignature() else {
        return nil
      }
      switch signature {
      case ZipSignature.localHeader:
        break
      case ZipSignature.centralDirectoryEntry, ZipSignature.endOfCentralDirectory, ZipSignature.zip64EndOfCentralDirectory:
        return nil
      default:
        throw ZipExtractorError.corrupt("no local header where one should be")
      }
      let fixed = try reader.read(30)
      let nameLength = Int(fixed.uint16(at: 26))
      let extraLength = Int(fixed.uint16(at: 28))
      let variable = try reader.read(nameLength + extraLength)
      guard let path = String(data: variable.prefix(nameLength), encoding: .utf8) else {
        throw ZipExtractorError.unsupported("an entry name that is not UTF-8")
      }
      self.path = path
      flags = fixed.uint16(at: 6)
      method = fixed.uint16(at: 8)
      crc32 = fixed.uint32(at: 14)
      compressedSize = UInt64(fixed.uint32(at: 18))
      size = UInt64(fixed.uint32(at: 22))
      modified = ZipCentralDirectory.dosDate(date: fixed.uint16(at: 12), time: fixed.uint16(at: 10))
      guard flags & 1 == 0 else {
        throw ZipExtractorError.unsupported("\(path) is encrypted")
      }
      guard method == 0 || method == 8 else {
        throw ZipExtractorError.unsupported("\(path) uses compression method \(method)")
      }
      // A stored entry's end can only be found from its size.
      guard method == 8 || flags & 8 == 0 else {
        throw ZipExtractorError.unsupported("\(path) is stored with its size after it")
      }
      try applyExtraFields(Data(variable.suffix(extraLength)))
    }

    private mutating func applyExtraFields(_ extra: Data) throws {
      var offset = 0
      while offset + 4 <= extra.count {
        let id = extra.uint16(at: offset)
        let size = Int(extra.uint16(at: offset + 2))
        let data = offset + 4
        guard data + size <= extra.count else {
          throw ZipExtractorError.corrupt("\(path) has a truncated extra field")
        }
        switch id {
        case 0x0001 where size >= 16:
          // In a local header, both sizes are present, uncompressed first.
          zip64 = true
          self.size = extra.uint64(at: data)
          compressedSize = extra.uint64(at: data + 8)
        case 0x5455 where size >= 5 && extra[extra.startIndex + data] & 1 != 0:
          modified = Date(timeIntervalSince1970: TimeInterval(Int32(bitPattern: extra.uint32(at: data + 1))))
        case 0x5855 where size >= 8:
          modified = Date(timeIntervalSince1970: TimeInterval(Int32(bitPattern: extra.uint32(at: data + 4))))
        default:
          break
        }
        offset = data + size
      }
    }
  }

  private struct Reader {
    let fileDescriptor: Int32
    private var buffer = [UInt8](repeating: 0, count: 1 << 20)
    private var start = 0
    private var end = 0

    init(fileDescriptor: Int32) {
      self.fileDescriptor = fileDescriptor
    }

    private var available: Int { end - start }

    /// Reads more after what is buffered, returning false at the end of the input.
    private mutating func fill() throws -> Bool {
      if start > 0 {
        let (from, count) = (start, available)
        buffer.withUnsafeMutableBytes { bytes in
          guard let base = bytes.baseAddress else {
            return
          }
          memmove(base, base + from, count)
        }
        end = count
        start = 0
      }
      while true {
        let (fd, offset) = (fileDescriptor, end)
        let count = buffer.withUnsafeMutableBytes { bytes in
          Darwin.read(fd, bytes.baseAddress.map { $0 + offset }, bytes.count - offset)
        }
        if count < 0 && errno == EINTR {
          continue
        }
        guard count >= 0 else {
          throw POSIXError.current
        }
        end += count
        return count > 0
      }
    }

    private mutating func ensure(_ count: Int) throws {
      while available < count {
        guard try fill() else {
          throw ZipExtractorError.corrupt("the zip ends early")
        }
      }
    }

    /// Nil at the end of the input.
    mutating func peekSignature() throws -> UInt32? {
      while available < 4 {
        guard try fill() else {
          return nil
        }
      }
      return Data(buffer[start..<start + 4]).uint32(at: 0)
    }

    mutating func read(_ count: Int) throws -> Data {
      try ensure(count)
      defer { start += count }
      return Data(buffer[start..<start + count])
    }

    /// Reads to the end of the input, discarding it.
    mutating func drain() throws {
      start = 0
      end = 0
      while try fill() {
        start = 0
        end = 0
      }
    }

    /// Calls `output` with the entry's contents in order, checking their size and
    /// CRC, and returns their size.
    @discardableResult
    mutating func decode(_ header: LocalHeader, into output: (UnsafeRawBufferPointer) throws -> Void) throws -> UInt64 {
      var crc = zlib.crc32(0, nil, 0)
      var size: UInt64 = 0
      func emit(_ chunk: UnsafeRawBufferPointer) throws {
        crc = zlib.crc32(crc, chunk.bindMemory(to: Bytef.self).baseAddress, uInt(chunk.count))
        size += UInt64(chunk.count)
        try output(chunk)
      }
      if header.method == 0 {
        var remaining = header.compressedSize
        while remaining > 0 {
          if available == 0 {
            try ensure(1)
          }
          let count = Int(min(UInt64(available), remaining))
          try buffer.withUnsafeBytes { try emit(UnsafeRawBufferPointer(rebasing: $0[start..<start + count])) }
          start += count
          remaining -= UInt64(count)
        }
      } else {
        try inflate(header.path, into: emit)
      }
      var expected = (crc32: header.crc32, size: header.size)
      if header.flags & 8 != 0 {
        if try peekSignature() == ZipSignature.dataDescriptor {
          start += 4
        }
        let width = header.zip64 ? 8 : 4
        let descriptor = try read(4 + 2 * width)
        expected = (descriptor.uint32(at: 0), header.zip64 ? descriptor.uint64(at: 12) : UInt64(descriptor.uint32(at: 8)))
      }
      guard size == expected.size, UInt32(crc) == expected.crc32 else {
        throw ZipExtractorError.corrupt("\(header.path) does not match its size or CRC")
      }
      return size
    }

    private mutating func inflate(_ path: String, into output: (UnsafeRawBufferPointer) throws -> Void) throws {
      var stream = z_stream()
      // Negative window bits: a zip holds raw deflate, without a zlib header.
      guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
        throw ZipExtractorError.corrupt("cannot inflate \(path)")
      }
      defer { inflateEnd(&stream) }
      var decompressed = [UInt8](repeating: 0, count: 1 << 18)
      while true {
        if available == 0 {
          try ensure(1)
        }
        let (offset, before) = (start, available)
        let status = buffer.withUnsafeMutableBytes { input in
          decompressed.withUnsafeMutableBytes { out in
            stream.next_in = input.bindMemory(to: Bytef.self).baseAddress.map { $0 + offset }
            stream.avail_in = uInt(before)
            stream.next_out = out.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(out.count)
            return zlib.inflate(&stream, Z_NO_FLUSH)
          }
        }
        start += before - Int(stream.avail_in)
        guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
          throw ZipExtractorError.corrupt("\(path) does not inflate")
        }
        let produced = decompressed.count - Int(stream.avail_out)
        try decompressed.withUnsafeBytes { try output(UnsafeRawBufferPointer(rebasing: $0[0..<produced])) }
        if status == Z_STREAM_END {
          return
        }
      }
    }
  }
}

extension ZipStreamExtractor {

  /// Extracts the zip written to `input`, reading it as a subprocess would read its stdin.
  public static func extract(_ input: FBProcessInput<AnyObject>, to root: String, overrideModificationTime: Bool, logger: any ControlCoreLogger) async throws {
    let fileDescriptor = try await bridgeFBFuture(input.attach()).fileDescriptor
    let start = Date()
    let result = await offCooperativePool {
      try extract(from: fileDescriptor, to: root, overrideModificationTime: overrideModificationTime)
    }
    _ = try? await bridgeFBFuture(input.detach())
    let summary = try result.get()
    logger.log("Extracted \(summary.files) files, \(summary.bytes) bytes, from a zip stream in-process in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
  }
}
