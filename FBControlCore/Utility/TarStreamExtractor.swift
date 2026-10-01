/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum TarExtractorError: Error, Equatable {
  case unsupported(String)
  case corrupt(String)
  case unsafePath(String)
}

/// Extracts a tar, or a gzipped tar, read forwards as it arrives, decoding on the
/// calling thread and writing several files at once.
///
/// What it writes matches `bsdtar -xp --no-mac-metadata`: modes and modification
/// times are applied, symlinks and hard links are made, nothing is written
/// through a symlink, extended attributes are restored from pax headers, and
/// AppleDouble `._` entries are skipped. An entry that is neither a file, a
/// directory nor a link fails the extraction, as does a path named twice.
public enum TarStreamExtractor {

  /// Reads up to the buffer's size into it, returning 0 at the end of the input.
  public typealias Read = (UnsafeMutableRawBufferPointer) throws -> Int

  /// Time the decoding thread spent blocked, which says whether the input or
  /// the disk held the extraction back.
  public struct Waits: Sendable {
    public var input: TimeInterval
    public var writers: TimeInterval
  }

  public enum Outcome {
    case extracted(ArchiveExtractionSummary, Waits)
    /// The input does not start with a tar header. `prefix` is everything read
    /// from it, decompressed, and `rest` reads what follows.
    case notTar(prefix: Data, rest: Read)
  }

  public static func reading(fileDescriptor: Int32) -> Read {
    { buffer in
      while true {
        let count = Darwin.read(fileDescriptor, buffer.baseAddress, buffer.count)
        if count >= 0 {
          return count
        }
        guard errno == EINTR else {
          throw POSIXError.current
        }
      }
    }
  }

  public static func extract(reading read: @escaping Read, to root: String, overrideModificationTime: Bool = false) throws -> Outcome {
    var inputWait: TimeInterval = 0
    let decoder = Decoder { buffer in
      let start = DispatchTime.now().uptimeNanoseconds
      defer { inputWait += Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9 }
      return try read(buffer)
    }
    var reader = Reader(decoder)
    guard let first = try reader.peekBlock(), Header.hasValidChecksum(first) else {
      return .notTar(prefix: reader.buffered, rest: decoder.read)
    }
    let writer = ParallelFileWriter(overrideModificationTime: overrideModificationTime)
    var summary = ArchiveExtractionSummary(files: 0, bytes: 0)
    var directories: [(path: String, mode: mode_t, modified: timespec)] = []
    var hardlinks: [(path: String, target: String)] = []
    do {
      // A symlink is never recorded as created, so no entry can be written through one:
      // making a directory where a symlink is fails.
      var created = ArchiveExtraction.Directories(root: root)
      var files: Set<String> = []
      var pax: [String: [UInt8]] = [:]
      var longName: String?
      var longLink: String?
      while let block = try reader.block() {
        if block.allSatisfy({ $0 == 0 }) {
          break
        }
        let header = try Header(block)
        var size = header.size
        switch header.type {
        case UInt8(ascii: "x"):
          pax = try parsePax(reader.metadata(size))
          continue
        case UInt8(ascii: "g"):
          try reader.skip(size)
          continue
        case UInt8(ascii: "L"):
          longName = try Header.string([UInt8](reader.metadata(size))[...])
          continue
        case UInt8(ascii: "K"):
          longLink = try Header.string([UInt8](reader.metadata(size))[...])
          continue
        default:
          break
        }
        let path = try paxString(pax, "path") ?? longName ?? header.name
        let link = try paxString(pax, "linkpath") ?? longLink ?? header.linkName
        let attributes = extendedAttributes(pax)
        if let paxSize = try paxString(pax, "size") {
          guard let value = UInt64(paxSize) else {
            throw TarExtractorError.corrupt("\(path) has a size of \(paxSize)")
          }
          size = value
        }
        let modified = try paxString(pax, "mtime").flatMap(Self.time) ?? header.modified
        (pax, longName, longLink) = ([:], nil, nil)

        // bsdtar reads these as the metadata of the entry that follows.
        let name = (path as NSString).lastPathComponent
        if name.hasPrefix("._"), name.count > 2 {
          try reader.skip(size)
          continue
        }
        let relative = try relativePath(path)
        let destination = (root as NSString).appendingPathComponent(relative)
        switch header.type {
        case UInt8(ascii: "5"):
          try reader.skip(size)
          guard !relative.isEmpty else {
            continue
          }
          try created.create(relative)
          directories.append((destination, header.mode, modified))
          setExtendedAttributes(attributes, on: destination)
        case UInt8(ascii: "0"), 0, UInt8(ascii: "7"):
          guard !relative.isEmpty, !path.hasSuffix("/") else {
            // A pre-POSIX tar marks a directory only by its trailing slash.
            try reader.skip(size)
            try created.create(relative)
            if !relative.isEmpty {
              directories.append((destination, header.mode, modified))
            }
            continue
          }
          try created.create((relative as NSString).deletingLastPathComponent)
          try writer.write(destination, mode: header.mode, modified: modified, extendedAttributes: attributes) {
            try reader.contents(size, into: $0)
          }
          files.insert(relative)
          summary.files += 1
          summary.bytes += size
        case UInt8(ascii: "2"):
          try reader.skip(size)
          guard !relative.isEmpty else {
            throw TarExtractorError.unsafePath(path)
          }
          try created.create((relative as NSString).deletingLastPathComponent)
          guard symlink(link, destination) == 0 else {
            throw POSIXError.current
          }
          setExtendedAttributes(attributes, on: destination)
          if !overrideModificationTime {
            try setTimes(modified, on: destination, flags: AT_SYMLINK_NOFOLLOW)
          }
        case UInt8(ascii: "1"):
          try reader.skip(size)
          let target = try relativePath(link)
          guard files.contains(target), !relative.isEmpty else {
            throw TarExtractorError.unsupported("\(path) is a hard link to \(link), which is not a file extracted before it")
          }
          try created.create((relative as NSString).deletingLastPathComponent)
          hardlinks.append((destination, (root as NSString).appendingPathComponent(target)))
        default:
          throw TarExtractorError.unsupported("\(path) has type \(Character(Unicode.Scalar(header.type)))")
        }
      }
      try reader.drain()
    } catch {
      writer.fail(error)
    }
    try writer.finish()
    // Once their targets are written.
    for (path, target) in hardlinks {
      guard linkat(AT_FDCWD, target, AT_FDCWD, path, 0) == 0 else {
        throw POSIXError.current
      }
    }
    // Deepest first, as a directory's mode may deny writing into it, and after
    // everything else, as writing into a directory changes its time.
    for (path, mode, modified) in directories.sorted(by: { $0.path.count > $1.path.count }) {
      if !overrideModificationTime {
        try setTimes(modified, on: path, flags: 0)
      }
      guard chmod(path, mode & 0o7777) == 0 else {
        throw POSIXError.current
      }
    }
    return .extracted(summary, Waits(input: inputWait, writers: writer.waited))
  }

  // MARK: - Private

  private static func setTimes(_ modified: timespec, on path: String, flags: Int32) throws {
    let times = [modified, modified]
    guard utimensat(AT_FDCWD, path, times, flags) == 0 else {
      throw POSIXError.current
    }
  }

  /// A pax time, `<seconds>[.<fraction>]`, to the nanosecond as `bsdtar` keeps it.
  private static func time(_ value: String) -> timespec? {
    let parts = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard let seconds = Int(parts[0]) else {
      return nil
    }
    guard parts.count == 2 else {
      return timespec(tv_sec: seconds, tv_nsec: 0)
    }
    let digits = parts[1].prefix(9)
    guard let fraction = Int(digits.padding(toLength: 9, withPad: "0", startingAt: 0)) else {
      return nil
    }
    guard value.hasPrefix("-"), fraction > 0 else {
      return timespec(tv_sec: seconds, tv_nsec: fraction)
    }
    return timespec(tv_sec: seconds - 1, tv_nsec: 1_000_000_000 - fraction)
  }

  /// Best effort, as for `bsdtar`: some attributes are the system's to set.
  private static func setExtendedAttributes(_ attributes: [String: Data], on path: String) {
    for (name, value) in attributes {
      _ = value.withUnsafeBytes { setxattr(path, name, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }
    }
  }

  /// Strips a leading `/` and `.` components, as `bsdtar` does, and refuses `..`.
  private static func relativePath(_ path: String) throws -> String {
    var components: [Substring] = []
    for component in path.split(separator: "/") where component != "." {
      guard component != ".." else {
        throw TarExtractorError.unsafePath(path)
      }
      components.append(component)
    }
    return components.joined(separator: "/")
  }

  /// Records of the form `<length> <key>=<value>\n`, where the length counts the
  /// whole record. Values are bytes: an extended attribute's need not be text.
  private static func parsePax(_ data: Data) throws -> [String: [UInt8]] {
    let bytes = [UInt8](data)
    var records: [String: [UInt8]] = [:]
    var offset = 0
    while offset < bytes.count {
      guard let space = bytes[offset...].firstIndex(of: UInt8(ascii: " ")),
        let length = Int(String(decoding: bytes[offset..<space], as: UTF8.self)),
        length > space - offset, offset + length <= bytes.count, bytes[offset + length - 1] == UInt8(ascii: "\n")
      else {
        throw TarExtractorError.corrupt("a malformed pax header")
      }
      let record = bytes[(space + 1)..<(offset + length - 1)]
      guard let equals = record.firstIndex(of: UInt8(ascii: "=")) else {
        throw TarExtractorError.corrupt("a malformed pax header")
      }
      records[String(decoding: record[..<equals], as: UTF8.self)] = Array(record[(equals + 1)...])
      offset += length
    }
    return records
  }

  /// As `bsdtar` reads them: the base64 `LIBARCHIVE.xattr.` form, with a
  /// percent-encoded name, over the raw `SCHILY.xattr.` form.
  private static func extendedAttributes(_ pax: [String: [UInt8]]) -> [String: Data] {
    var attributes: [String: Data] = [:]
    for (key, value) in pax where key.hasPrefix("SCHILY.xattr.") {
      attributes[String(key.dropFirst("SCHILY.xattr.".count))] = Data(value)
    }
    for (key, value) in pax where key.hasPrefix("LIBARCHIVE.xattr.") {
      if let name = String(key.dropFirst("LIBARCHIVE.xattr.".count)).removingPercentEncoding,
        let decoded = Data(base64Encoded: Self.padBase64(value))
      {
        attributes[name] = decoded
      }
    }
    return attributes
  }

  /// libarchive writes base64 without its trailing padding.
  private static func padBase64(_ value: [UInt8]) -> Data {
    Data(value + Array(repeating: UInt8(ascii: "="), count: (4 - value.count % 4) % 4))
  }

  private static func paxString(_ pax: [String: [UInt8]], _ key: String) throws -> String? {
    guard let value = pax[key] else {
      return nil
    }
    guard let string = String(bytes: value, encoding: .utf8) else {
      throw TarExtractorError.unsupported("a pax \(key) that is not UTF-8")
    }
    return string
  }

  private struct Header {
    var name: String
    var linkName: String
    var mode: mode_t
    var size: UInt64
    var modified: timespec
    var type: UInt8

    init(_ block: [UInt8]) throws {
      guard Self.hasValidChecksum(block) else {
        throw TarExtractorError.corrupt("a tar header with the wrong checksum")
      }
      name = try Self.string(block[0..<100])
      mode = mode_t(try Self.number(block[100..<108]) & 0o7777)
      size = try Self.number(block[124..<136])
      modified = timespec(tv_sec: Int(try Self.number(block[136..<148])), tv_nsec: 0)
      type = block[156]
      linkName = try Self.string(block[157..<257])
      // POSIX ustar only: GNU tar keeps other fields where the prefix would be.
      if block[257..<263].elementsEqual(Array("ustar\0".utf8)) {
        let prefix = try Self.string(block[345..<500])
        if !prefix.isEmpty {
          name = prefix + "/" + name
        }
      }
    }

    static func hasValidChecksum(_ block: [UInt8]) -> Bool {
      guard block.count == 512, let stored = try? number(block[148..<156]) else {
        return false
      }
      var unsigned: Int64 = 0
      var signed: Int64 = 0
      for (index, byte) in block.enumerated() {
        let value = (148..<156).contains(index) ? UInt8(ascii: " ") : byte
        unsigned += Int64(value)
        signed += Int64(Int8(bitPattern: value))
      }
      return Int64(stored) == unsigned || Int64(stored) == signed
    }

    static func string(_ field: ArraySlice<UInt8>) throws -> String {
      let bytes = field.prefix { $0 != 0 }
      guard let string = String(bytes: bytes, encoding: .utf8) else {
        throw TarExtractorError.unsupported("a name that is not UTF-8")
      }
      return string
    }

    /// Octal, padded with spaces or NULs, or GNU's base-256 for larger values.
    static func number(_ field: ArraySlice<UInt8>) throws -> UInt64 {
      if let first = field.first, first & 0x80 != 0 {
        guard first == 0x80 else {
          throw TarExtractorError.unsupported("a negative number in a tar header")
        }
        var value: UInt64 = 0
        for byte in field.dropFirst() {
          guard value >> 56 == 0 else {
            throw TarExtractorError.unsupported("a number too large in a tar header")
          }
          value = value << 8 | UInt64(byte)
        }
        return value
      }
      var value: UInt64 = 0
      var digits = false
      for byte in field {
        if byte == 0 || byte == UInt8(ascii: " ") {
          if digits {
            break
          }
          continue
        }
        guard (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(byte), value >> 60 == 0 else {
          throw TarExtractorError.corrupt("a malformed number in a tar header")
        }
        value = value << 3 | UInt64(byte - UInt8(ascii: "0"))
        digits = true
      }
      return value
    }
  }

  private struct Reader {
    let decoder: Decoder
    private var input: BufferedInput

    init(_ decoder: Decoder) {
      self.decoder = decoder
      input = BufferedInput(capacity: 1 << 20, read: decoder.read)
    }

    var buffered: Data { input.buffered }

    /// The next block without consuming it, or nil if the input ends first.
    mutating func peekBlock() throws -> [UInt8]? {
      guard try input.buffer(atLeast: 512) else {
        return nil
      }
      return input.withAvailable { Array($0[0..<512]) }
    }

    /// Nil at the end of the input. An archive without the blocks of zeros that
    /// should end it is taken as complete, as `bsdtar` does.
    mutating func block() throws -> [UInt8]? {
      guard let block = try peekBlock() else {
        guard input.available == 0 else {
          throw TarExtractorError.corrupt("the tar ends partway through a header")
        }
        return nil
      }
      input.consume(512)
      return block
    }

    /// Calls `output` with the next `size` bytes, then skips the padding after them.
    mutating func contents(_ size: UInt64, into output: (UnsafeRawBufferPointer) throws -> Void) throws {
      var remaining = size
      while remaining > 0 {
        guard try input.buffer(atLeast: 1) else {
          throw TarExtractorError.corrupt("the tar ends partway through an entry")
        }
        let count = Int(min(UInt64(input.available), remaining))
        try input.withAvailable { try output(UnsafeRawBufferPointer(rebasing: $0[0..<count])) }
        input.consume(count)
        remaining -= UInt64(count)
      }
      var padding = Int((512 - size % 512) % 512)
      while padding > 0 {
        guard try input.buffer(atLeast: 1) else {
          throw TarExtractorError.corrupt("the tar ends partway through an entry")
        }
        let count = min(input.available, padding)
        input.consume(count)
        padding -= count
      }
    }

    mutating func skip(_ size: UInt64) throws {
      try contents(size) { _ in }
    }

    /// The contents of an entry describing the next, which are bounded to keep a
    /// corrupt size from exhausting memory.
    mutating func metadata(_ size: UInt64) throws -> Data {
      guard size <= 1 << 20 else {
        throw TarExtractorError.unsupported("a tar metadata entry of \(size) bytes")
      }
      var data = Data()
      try contents(size) { data.append(contentsOf: $0) }
      return data
    }

    /// Reads to the end of the input, discarding it, so a writer is never left
    /// blocked on a pipe that nothing reads.
    mutating func drain() throws {
      input.discard()
      try decoder.drain()
    }
  }

  /// Passes the input through, inflating it first if it is gzipped.
  private final class Decoder {
    private enum State {
      case undetected
      case plain
      case gzip(Inflater)
      case finished
    }

    private var state = State.undetected
    private var input: BufferedInput

    init(_ raw: @escaping Read) {
      input = BufferedInput(capacity: 1 << 18, read: raw)
    }

    func read(_ output: UnsafeMutableRawBufferPointer) throws -> Int {
      switch state {
      case .undetected:
        guard try input.buffer(atLeast: 2), input[0] == 0x1F, input[1] == 0x8B else {
          state = .plain
          return try read(output)
        }
        guard let inflater = Inflater(.gzip) else {
          throw TarExtractorError.corrupt("cannot inflate the gzip")
        }
        state = .gzip(inflater)
        return try read(output)
      case .plain:
        return try input.read(into: output)
      case .gzip(let inflater):
        return try inflate(inflater, into: output)
      case .finished:
        return 0
      }
    }

    /// Reads the raw input to its end.
    func drain() throws {
      state = .finished
      try input.drain()
    }

    private func inflate(_ inflater: Inflater, into output: UnsafeMutableRawBufferPointer) throws -> Int {
      while true {
        guard try input.buffer(atLeast: 1) else {
          throw TarExtractorError.corrupt("the gzip ends early")
        }
        guard let step = input.withAvailable({ inflater.inflate($0, into: output) }) else {
          throw TarExtractorError.corrupt("the gzip does not inflate")
        }
        input.consume(step.consumed)
        var finished = false
        if step.ended {
          // gzip allows several members one after another; anything else after one is ignored.
          if try input.buffer(atLeast: 2), input[0] == 0x1F, input[1] == 0x8B {
            inflater.reset()
          } else {
            state = .finished
            finished = true
          }
        }
        if step.produced > 0 || finished {
          return step.produced
        }
      }
    }
  }
}
