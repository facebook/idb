/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Writes stored zips entry by entry, for archives no producer will write: absolute and escaping names, symlinks that
/// later entries are written through.
struct ZipBuilder {

  struct Entry {
    let name: String
    let contents: Data
    let mode: UInt32

    static func file(_ name: String, _ contents: String = "contents") -> Entry {
      Entry(name: name, contents: Data(contents.utf8), mode: 0o100644)
    }

    static func directory(_ name: String) -> Entry {
      Entry(name: name.hasSuffix("/") ? name : name + "/", contents: Data(), mode: 0o040755)
    }

    static func symlink(_ name: String, to destination: String) -> Entry {
      Entry(name: name, contents: Data(destination.utf8), mode: 0o120755)
    }
  }

  static func zip(_ entries: [Entry]) -> Data {
    var archive = Data()
    var centralDirectory = Data()
    for entry in entries {
      let offset = UInt32(archive.count)
      let name = Data(entry.name.utf8)
      let crc = crc32(entry.contents)
      archive.append(le32(0x0403_4B50))
      archive.append(le16(20))
      archive.append(le16(0))
      archive.append(le16(0))
      archive.append(le16(0))
      archive.append(le16(0x21))
      archive.append(le32(crc))
      archive.append(le32(UInt32(entry.contents.count)))
      archive.append(le32(UInt32(entry.contents.count)))
      archive.append(le16(UInt16(name.count)))
      archive.append(le16(0))
      archive.append(name)
      archive.append(entry.contents)

      // Made by Unix (3), so that the external attributes hold the mode.
      centralDirectory.append(le32(0x0201_4B50))
      centralDirectory.append(le16(0x0314))
      centralDirectory.append(le16(20))
      centralDirectory.append(le16(0))
      centralDirectory.append(le16(0))
      centralDirectory.append(le16(0))
      centralDirectory.append(le16(0x21))
      centralDirectory.append(le32(crc))
      centralDirectory.append(le32(UInt32(entry.contents.count)))
      centralDirectory.append(le32(UInt32(entry.contents.count)))
      centralDirectory.append(le16(UInt16(name.count)))
      centralDirectory.append(le16(0))
      centralDirectory.append(le16(0))
      centralDirectory.append(le16(0))
      centralDirectory.append(le16(0))
      centralDirectory.append(le32(entry.mode << 16))
      centralDirectory.append(le32(offset))
      centralDirectory.append(name)
    }
    let directoryOffset = UInt32(archive.count)
    archive.append(centralDirectory)
    archive.append(le32(0x0605_4B50))
    archive.append(le16(0))
    archive.append(le16(0))
    archive.append(le16(UInt16(entries.count)))
    archive.append(le16(UInt16(entries.count)))
    archive.append(le32(UInt32(centralDirectory.count)))
    archive.append(le32(directoryOffset))
    archive.append(le16(0))
    return archive
  }

  private static func le16(_ value: UInt16) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
  }

  private static func le32(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
  }

  private static let crcTable: [UInt32] = (0..<256).map { index in
    (0..<8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
  }

  private static func crc32(_ data: Data) -> UInt32 {
    ~data.reduce(~UInt32(0)) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
  }
}
