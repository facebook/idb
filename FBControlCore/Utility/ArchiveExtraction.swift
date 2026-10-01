/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// What an in-process extractor wrote.
public struct ArchiveExtractionSummary: Equatable, Sendable {
  public var files: Int
  public var bytes: UInt64

  func description(from source: String, since start: Date) -> String {
    "Extracted \(files) files, \(bytes) bytes, from \(source) in-process in \(String(format: "%.2f", Date().timeIntervalSince(start)))s"
  }
}

/// The file system work shared by the in-process extractors.
enum ArchiveExtraction {

  /// Creating a small file is mostly waiting, on the file system and on any
  /// endpoint security agent inspecting it, rather than work for a core.
  static let writerCount = 8

  static func makeDirectory(_ path: String) throws {
    if mkdir(path, 0o755) == 0 {
      return
    }
    let error = POSIXError.current
    var info = stat()
    guard error.code == .EEXIST, lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
      throw error
    }
  }

  static func setTimes(_ date: Date, apply: (UnsafePointer<timeval>) -> Int32) throws {
    let seconds = date.timeIntervalSince1970.rounded(.down)
    let time = timeval(tv_sec: Int(seconds), tv_usec: Int32((date.timeIntervalSince1970 - seconds) * 1_000_000))
    let times = [time, time]
    guard apply(times) == 0 else {
      throw POSIXError.current
    }
  }

  static func isMacMetadata(_ relative: String) -> Bool {
    relative == "__MACOSX" || relative.hasPrefix("__MACOSX/")
  }

  /// Clears a failed extraction before the next extractor writes into the same place.
  /// Best effort: whatever cannot be removed is overwritten, or fails that extractor with its own error.
  static func removeContents(of directory: String) {
    for item in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] {
      try? FileManager.default.removeItem(atPath: (directory as NSString).appendingPathComponent(item))
    }
  }

  /// Makes the directories entries are written into, each once, as an archive read forwards names them.
  struct Directories {
    let root: String
    private var created: Set<String> = []

    init(root: String) {
      self.root = root
    }

    mutating func create(_ relative: String) throws {
      guard !relative.isEmpty, !created.contains(relative) else {
        return
      }
      try create((relative as NSString).deletingLastPathComponent)
      try makeDirectory((root as NSString).appendingPathComponent(relative))
      created.insert(relative)
    }
  }
}

extension POSIXError {
  static var current: POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
}
