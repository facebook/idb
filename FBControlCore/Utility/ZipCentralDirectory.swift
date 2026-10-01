/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import os

public enum ZipCentralDirectoryError: Error, Equatable {
  case noEndOfCentralDirectory
  case truncated
  case undecodableName
  case unsafePath(String)
  case unexpectedFileType(String)
}

/// Record signatures, as read little-endian from the file.
public enum ZipSignature {
  public static let localHeaderBytes = Data([0x50, 0x4B, 0x03, 0x04])
  static let localHeader: UInt32 = 0x0403_4B50
  static let dataDescriptor: UInt32 = 0x0807_4B50
  static let centralDirectoryEntry: UInt32 = 0x0201_4B50
  static let endOfCentralDirectory: UInt32 = 0x0605_4B50
  static let zip64EndOfCentralDirectory: UInt32 = 0x0606_4B50
  static let zip64Locator: UInt32 = 0x0706_4B50
}

/// The index at the end of a zip, which is the only place a zip records
/// symlinks and permissions. A reader of the zip as a stream never reaches it.
public struct ZipCentralDirectory {

  public struct Entry: Equatable {
    public var path: String

    /// The unix mode, when the archiver recorded one.
    public var mode: mode_t?

    public var flags: UInt16 = 0
    public var method: UInt16 = 0
    public var crc32: UInt32 = 0
    public var compressedSize: UInt64 = 0
    public var size: UInt64 = 0
    public var localHeaderOffset: UInt64 = 0

    /// From the extended timestamp when there is one, else the local-time DOS stamp.
    public var modified: Date?

    public init(path: String, mode: mode_t?) {
      self.path = path
      self.mode = mode
    }
  }

  public let entries: [Entry]

  public init(entries: [Entry]) {
    self.entries = entries
  }

  public init(archiveAtPath path: String) throws {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    let size = try handle.seekToEnd()
    let (count, length, offset) = try Self.locate(in: handle, size: size)
    try handle.seek(toOffset: offset)
    guard let directory = try handle.read(upToCount: Int(length)), directory.count == length else {
      throw ZipCentralDirectoryError.truncated
    }
    entries = try Self.parse(directory, count: count)
  }

  /// Makes a tree extracted from the zip as a stream what extracting the complete
  /// file would have made: permissions and symlinks are applied, and AppleDouble
  /// entries for another entry, which only a complete-file extraction folds away,
  /// are removed.
  public func repair(extractedAt root: String) throws {
    let paths = Set(entries.map { Self.trimmingTrailingSlash($0.path) })
    var verifiedDirectories: Set<String> = [""]
    var symlinks: [String] = []
    var files: [(path: String, mode: mode_t)] = []
    var directories: [(path: String, mode: mode_t)] = []
    var sequestered = false
    for entry in entries {
      let relative = try Self.safeRelativePath(entry.path)
      if relative.hasPrefix("__MACOSX/") {
        sequestered = true
        continue
      }
      // The central directory need not agree with the entries that were
      // extracted, so nothing here may be reached through a symlink.
      try Self.verifyNoSymlinkAncestors(of: relative, in: root, verified: &verifiedDirectories)
      let path = (root as NSString).appendingPathComponent(relative)
      if Self.isAppleDouble(relative, alongside: paths), Self.hasAppleDoubleHeader(atPath: path) {
        try FileManager.default.removeItem(atPath: path)
        continue
      }
      guard let mode = entry.mode, mode != 0 else {
        continue
      }
      switch mode & S_IFMT {
      case S_IFLNK:
        symlinks.append(path)
      case S_IFDIR:
        directories.append((path, mode))
      case S_IFREG, 0:
        files.append((path, mode))
      default:
        continue
      }
    }
    try Self.setPermissions(of: files)
    if sequestered {
      try? FileManager.default.removeItem(atPath: (root as NSString).appendingPathComponent("__MACOSX"))
    }
    for path in symlinks {
      try Self.replaceWithSymlink(path)
    }
    // Last and deepest first, as a directory's mode may deny writing into it.
    for (path, mode) in directories.sorted(by: { $0.path.count > $1.path.count }) {
      try Self.setPermissions(mode, atPath: path)
    }
  }

  // MARK: - Private

  private static let unixHost: UInt16 = 3
  static let appleDoubleMagic = Data([0x00, 0x05, 0x16, 0x07])

  private static func locate(in handle: FileHandle, size: UInt64) throws -> (count: UInt64, length: UInt64, offset: UInt64) {
    // The record is 22 bytes, followed by a comment of at most 65535.
    let tailLength = min(size, 22 + 0xFFFF)
    try handle.seek(toOffset: size - tailLength)
    guard let tail = try handle.read(upToCount: Int(tailLength)), tail.count == tailLength, tail.count >= 22 else {
      throw ZipCentralDirectoryError.noEndOfCentralDirectory
    }
    guard let record = stride(from: tail.count - 22, through: 0, by: -1).first(where: { tail.uint32(at: $0) == ZipSignature.endOfCentralDirectory }) else {
      throw ZipCentralDirectoryError.noEndOfCentralDirectory
    }
    let recordOffset = size - tailLength + UInt64(record)
    if recordOffset >= 20 {
      try handle.seek(toOffset: recordOffset - 20)
      if let locator = try handle.read(upToCount: 20), locator.count == 20, locator.uint32(at: 0) == ZipSignature.zip64Locator {
        try handle.seek(toOffset: locator.uint64(at: 8))
        guard let zip64 = try handle.read(upToCount: 56), zip64.count == 56, zip64.uint32(at: 0) == ZipSignature.zip64EndOfCentralDirectory else {
          throw ZipCentralDirectoryError.truncated
        }
        return (zip64.uint64(at: 32), zip64.uint64(at: 40), zip64.uint64(at: 48))
      }
    }
    return (UInt64(tail.uint16(at: record + 10)), UInt64(tail.uint32(at: record + 12)), UInt64(tail.uint32(at: record + 16)))
  }

  private static func parse(_ directory: Data, count: UInt64) throws -> [Entry] {
    var entries: [Entry] = []
    var offset = 0
    for _ in 0..<count {
      guard offset + 46 <= directory.count, directory.uint32(at: offset) == ZipSignature.centralDirectoryEntry else {
        throw ZipCentralDirectoryError.truncated
      }
      let host = directory.uint16(at: offset + 4) >> 8
      let flags = directory.uint16(at: offset + 8)
      let method = directory.uint16(at: offset + 10)
      let dosTime = directory.uint16(at: offset + 12)
      let dosDate = directory.uint16(at: offset + 14)
      let crc32 = directory.uint32(at: offset + 16)
      let nameLength = Int(directory.uint16(at: offset + 28))
      let extraLength = Int(directory.uint16(at: offset + 30))
      let commentLength = Int(directory.uint16(at: offset + 32))
      let attributes = directory.uint32(at: offset + 38)
      let nameStart = directory.startIndex + offset + 46
      guard offset + 46 + nameLength <= directory.count else {
        throw ZipCentralDirectoryError.truncated
      }
      guard let path = String(data: directory[nameStart..<(nameStart + nameLength)], encoding: .utf8) else {
        throw ZipCentralDirectoryError.undecodableName
      }
      let extraStart = offset + 46 + nameLength
      guard extraStart + extraLength <= directory.count else {
        throw ZipCentralDirectoryError.truncated
      }
      var entry = Entry(path: path, mode: host == unixHost ? mode_t(attributes >> 16) : nil)
      entry.flags = flags
      entry.method = method
      entry.crc32 = crc32
      entry.compressedSize = UInt64(directory.uint32(at: offset + 20))
      entry.size = UInt64(directory.uint32(at: offset + 24))
      entry.localHeaderOffset = UInt64(directory.uint32(at: offset + 42))
      entry.modified = Self.dosDate(date: dosDate, time: dosTime)
      try Self.applyExtraFields(directory, from: extraStart, length: extraLength, to: &entry)
      entries.append(entry)
      offset += 46 + nameLength + extraLength + commentLength
    }
    return entries
  }

  private static let zip64ExtraField: UInt16 = 0x0001
  private static let extendedTimestampExtraField: UInt16 = 0x5455
  /// The Info-ZIP Unix field that `ditto` writes instead of the extended timestamp.
  private static let infoZipUnixExtraField: UInt16 = 0x5855

  private static func applyExtraFields(_ directory: Data, from start: Int, length: Int, to entry: inout Entry) throws {
    var offset = start
    while offset + 4 <= start + length {
      let id = directory.uint16(at: offset)
      let size = Int(directory.uint16(at: offset + 2))
      let data = offset + 4
      guard data + size <= start + length else {
        throw ZipCentralDirectoryError.truncated
      }
      switch id {
      case zip64ExtraField:
        // Only the fields saturated in the fixed record are present, in this order.
        var field = data
        func next() throws -> UInt64 {
          guard field + 8 <= data + size else {
            throw ZipCentralDirectoryError.truncated
          }
          defer { field += 8 }
          return directory.uint64(at: field)
        }
        if entry.size == 0xFFFF_FFFF {
          entry.size = try next()
        }
        if entry.compressedSize == 0xFFFF_FFFF {
          entry.compressedSize = try next()
        }
        if entry.localHeaderOffset == 0xFFFF_FFFF {
          entry.localHeaderOffset = try next()
        }
      case extendedTimestampExtraField where size >= 5 && directory[directory.startIndex + data] & 1 != 0:
        entry.modified = Date(timeIntervalSince1970: TimeInterval(Int32(bitPattern: directory.uint32(at: data + 1))))
      case infoZipUnixExtraField where size >= 8:
        entry.modified = Date(timeIntervalSince1970: TimeInterval(Int32(bitPattern: directory.uint32(at: data + 4))))
      default:
        break
      }
      offset = data + size
    }
  }

  static func dosDate(date: UInt16, time: UInt16) -> Date? {
    var components = DateComponents()
    components.year = 1980 + Int(date >> 9)
    components.month = Int((date >> 5) & 0xF)
    components.day = Int(date & 0x1F)
    components.hour = Int(time >> 11)
    components.minute = Int((time >> 5) & 0x3F)
    components.second = Int(time & 0x1F) * 2
    return Calendar.current.date(from: components)
  }

  static func trimmingTrailingSlash(_ path: String) -> String {
    path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  static func safeRelativePath(_ path: String) throws -> String {
    let relative = trimmingTrailingSlash(path)
    guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else {
      throw ZipCentralDirectoryError.unsafePath(path)
    }
    return relative
  }

  static func isAppleDouble(_ path: String, alongside paths: Set<String>) -> Bool {
    let name = (path as NSString).lastPathComponent
    guard name.hasPrefix("._") else {
      return false
    }
    return paths.contains(((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(String(name.dropFirst(2))))
  }

  private static func hasAppleDoubleHeader(atPath path: String) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else {
      return false
    }
    defer { try? handle.close() }
    return (try? handle.read(upToCount: appleDoubleMagic.count)) == appleDoubleMagic
  }

  private static func verifyNoSymlinkAncestors(of relative: String, in root: String, verified: inout Set<String>) throws {
    let parent = (relative as NSString).deletingLastPathComponent
    guard !verified.contains(parent) else {
      return
    }
    try verifyNoSymlinkAncestors(of: parent, in: root, verified: &verified)
    let type = try FileManager.default.attributesOfItem(atPath: (root as NSString).appendingPathComponent(parent))[.type] as? FileAttributeType
    guard type == .typeDirectory else {
      throw ZipCentralDirectoryError.unexpectedFileType(parent)
    }
    verified.insert(parent)
  }

  /// A few writers at once roughly halve the time a large bundle takes; more
  /// than that contend.
  private static func setPermissions(of files: [(path: String, mode: mode_t)]) throws {
    let width = 4
    let failure = OSAllocatedUnfairLock<Error?>(initialState: nil)
    DispatchQueue.concurrentPerform(iterations: width) { worker in
      for index in stride(from: worker, to: files.count, by: width) {
        do {
          try setPermissions(files[index].mode, atPath: files[index].path)
        } catch {
          failure.withLock { $0 = $0 ?? error }
          return
        }
      }
    }
    if let firstError = failure.withLock({ $0 }) {
      throw firstError
    }
  }

  private static func setPermissions(_ mode: mode_t, atPath path: String) throws {
    guard fchmodat(AT_FDCWD, path, mode & 0o7777, AT_SYMLINK_NOFOLLOW) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private static func replaceWithSymlink(_ path: String) throws {
    // A stream carries a symlink as a regular file holding its target.
    let type = try FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType
    if type == .typeSymbolicLink {
      return
    }
    guard type == .typeRegular else {
      throw ZipCentralDirectoryError.unexpectedFileType(path)
    }
    let target = try String(contentsOfFile: path, encoding: .utf8)
    try FileManager.default.removeItem(atPath: path)
    try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
  }
}

extension Data {
  func uint16(at offset: Int) -> UInt16 {
    let start = startIndex + offset
    return UInt16(self[start]) | UInt16(self[start + 1]) << 8
  }

  func uint32(at offset: Int) -> UInt32 {
    UInt32(uint16(at: offset)) | UInt32(uint16(at: offset + 2)) << 16
  }

  func uint64(at offset: Int) -> UInt64 {
    UInt64(uint32(at: offset)) | UInt64(uint32(at: offset + 4)) << 32
  }
}
