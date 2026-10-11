/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import ArgumentParser
import FBArtifactStaging
import Foundation

/// How big an app fixture is, and across how many files: holding the size and varying the count separates per-byte
/// costs (transfer, decompression) from per-file costs (creating and writing files).
struct FixtureShape: Codable, Hashable {
  let megabytes: Int
  let files: Int

  static func parse(_ value: String) throws -> FixtureShape {
    let parts = value.split(separator: "x").compactMap { Int($0) }
    guard parts.count == 2, parts[0] > 0, parts[1] > 0 else {
      throw ValidationError("A fixture is <megabytes>x<files>, not \(value)")
    }
    // Files of no bytes would make a fixture whose throughput means nothing.
    guard parts[0] * 1_000_000 >= parts[1] else {
      throw ValidationError("A fixture of \(parts[0]) MB can't hold \(parts[1]) files of at least a byte each")
    }
    return FixtureShape(megabytes: parts[0], files: parts[1])
  }

  var name: String { "\(megabytes)x\(files)" }
}

enum FixtureContents: String, Codable, CaseIterable {
  /// Text that deflates and zstd-compresses several times over.
  case compressible
  /// Seeded random bytes, which no compressor shrinks.
  case incompressible

  static func parse(_ value: String) throws -> FixtureContents {
    guard let contents = FixtureContents(rawValue: value) else {
      throw ValidationError("Unknown contents \(value)")
    }
    return contents
  }
}

/// How the archive is packed.
enum BenchFormat: String, Codable, CaseIterable {
  /// A zip of stored entries, as an `.ipa` from a build usually is.
  case ipaStored = "ipa-stored"
  /// A zip of deflated entries.
  case ipaDeflated = "ipa-deflated"
  /// A stored zip in a zstd frame behind the zstd-zip marker, as clients that negotiate it stream an `.ipa`.
  case zipZstd = "zip-zstd"
  case tar
  case tarGzip = "tar-gz"
  case tarZstd = "tar-zst"

  static func parse(_ value: String) throws -> BenchFormat {
    guard let format = BenchFormat(rawValue: value) else {
      throw ValidationError("Unknown format \(value)")
    }
    return format
  }
}

/// Generates fixtures and their archives once, keyed by everything that determines their bytes, so repeated runs and
/// both sides of an A/B read the same files.
struct Fixtures {

  let root: URL

  private var fileManager: FileManager { .default }

  func archive(_ format: BenchFormat, shape: FixtureShape, contents: FixtureContents) throws -> URL {
    let directory = root.appendingPathComponent("\(shape.name)-\(contents.rawValue)")
    let archive = directory.appendingPathComponent("A.\(format.rawValue)")
    if fileManager.fileExists(atPath: archive.path) {
      return archive
    }
    let app = try self.app(shape: shape, contents: contents, in: directory)
    // `zip` adds `.zip` to a name that has no extension.
    let partial = directory.appendingPathComponent("partial-\(UUID().uuidString).zip")
    switch format {
    case .ipaStored:
      try run("/usr/bin/zip", ["-qry0", partial.path, app.lastPathComponent], in: directory)
    case .ipaDeflated:
      try run("/usr/bin/zip", ["-qry", partial.path, app.lastPathComponent], in: directory)
    case .tar:
      try run("/usr/bin/tar", ["-cf", partial.path, app.lastPathComponent], in: directory)
    case .tarGzip:
      try run("/usr/bin/tar", ["-czf", partial.path, app.lastPathComponent], in: directory)
    case .zipZstd:
      let stored = try self.archive(.ipaStored, shape: shape, contents: contents)
      try (ArchiveFormat.zstdZipMarker + zstd(try Data(contentsOf: stored))).write(to: partial)
    case .tarZstd:
      let tar = directory.appendingPathComponent("A.tar")
      if !fileManager.fileExists(atPath: tar.path) {
        try run("/usr/bin/tar", ["-cf", tar.path, app.lastPathComponent], in: directory)
      }
      try zstd(try Data(contentsOf: tar)).write(to: partial)
    }
    try fileManager.moveItem(at: partial, to: archive)
    return archive
  }

  private func app(shape: FixtureShape, contents: FixtureContents, in directory: URL) throws -> URL {
    let app = directory.appendingPathComponent("A.app")
    let marker = directory.appendingPathComponent(".complete")
    if fileManager.fileExists(atPath: marker.path) {
      return app
    }
    try? fileManager.removeItem(at: directory)
    let fileSize = shape.megabytes * 1_000_000 / shape.files
    var generator = SplitMix64(seed: UInt64(shape.megabytes * 7919 + shape.files))
    let text = Data(String(repeating: "the quick brown fox jumps over the lazy dog ", count: fileSize / 44 + 1).utf8.prefix(fileSize))
    for index in 0..<shape.files {
      let subdirectory = app.appendingPathComponent("Contents/\(index % 64)")
      try fileManager.createDirectory(at: subdirectory, withIntermediateDirectories: true)
      let bytes: Data
      switch contents {
      case .compressible:
        bytes = text
      case .incompressible:
        bytes = Data((0..<fileSize).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
      }
      try bytes.write(to: subdirectory.appendingPathComponent("file-\(index)"))
    }
    let plist: [String: Any] = ["CFBundleIdentifier": "com.example.staging-bench", "CFBundleExecutable": "A", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
    fileManager.createFile(atPath: marker.path, contents: nil)
    return app
  }

  /// zstd at level 3 when a `zstd` is installed; otherwise a frame of stored blocks, which decodes with no
  /// decompression work. Results record which, as `zstd`.
  static var zstdCompressor: String? {
    ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd"].first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  private func zstd(_ data: Data) throws -> Data {
    guard let compressor = Self.zstdCompressor else {
      return Self.storedZstdFrame(data)
    }
    let input = root.appendingPathComponent("zstd-in-\(UUID().uuidString)")
    let output = root.appendingPathComponent("zstd-out-\(UUID().uuidString)")
    try data.write(to: input)
    defer {
      try? fileManager.removeItem(at: input)
      try? fileManager.removeItem(at: output)
    }
    try run(compressor, ["-q", "-3", input.path, "-o", output.path], in: root)
    return try Data(contentsOf: output)
  }

  static func storedZstdFrame(_ data: Data) -> Data {
    var frame = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x38])
    var offset = data.startIndex
    repeat {
      let size = min(data.endIndex - offset, 1 << 17)
      let last = offset + size == data.endIndex
      let header = UInt32(size) << 3 | (last ? 1 : 0)
      frame.append(contentsOf: [UInt8(header & 0xFF), UInt8(header >> 8 & 0xFF), UInt8(header >> 16)])
      frame.append(data[offset..<offset + size])
      offset += size
    } while offset < data.endIndex
    return frame
  }

  private func run(_ launchPath: String, _ arguments: [String], in directory: URL) throws {
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw ValidationError("\(launchPath) \(arguments) exited \(process.terminationStatus)")
    }
  }
}

/// A seeded generator, so that incompressible fixtures are the same bytes on every host.
struct SplitMix64: RandomNumberGenerator {

  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
