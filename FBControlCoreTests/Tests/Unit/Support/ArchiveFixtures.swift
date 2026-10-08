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
import os

/// What the archive tests share: running the tools that write archives, and comparing what extractions leave behind.
enum ArchiveFixtures {

  struct ToolFailed: Error, CustomStringConvertible {
    let description: String
  }

  /// Throws rather than recording an issue, so that it fails XCTest cases as well as Swift Testing ones.
  static func run(_ launchPath: String, _ arguments: [String], in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw ToolFailed(description: "\(launchPath) \(arguments) exited \(process.terminationStatus)")
    }
  }

  /// An app with modes, symlinks, nesting, extended attributes and contents that deflate.
  static func makeApp(in root: URL) throws -> String {
    let fileManager = FileManager.default
    let app = root.appendingPathComponent("A.app")
    try fileManager.createDirectory(at: app.appendingPathComponent("Real/Deeper"), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: app.appendingPathComponent("Private"), withIntermediateDirectories: true)
    try Data("binary".utf8).write(to: app.appendingPathComponent("A"))
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("A").path)
    try Data("<plist/>".utf8).write(to: app.appendingPathComponent("Info.plist"))
    try Data(String(repeating: "compressible ", count: 200_000).utf8).write(to: app.appendingPathComponent("Real/Deeper/big.txt"))
    try Data().write(to: app.appendingPathComponent("Real/empty"))
    try Data("secret".utf8).write(to: app.appendingPathComponent("Private/key"))
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: app.appendingPathComponent("Private/key").path)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: app.appendingPathComponent("Private").path)
    try fileManager.createSymbolicLink(atPath: app.appendingPathComponent("link.plist").path, withDestinationPath: "Info.plist")
    try fileManager.createSymbolicLink(atPath: app.appendingPathComponent("LinkDir").path, withDestinationPath: "Real")
    try run("/usr/bin/xattr", ["-w", "com.example.tag", "value", app.appendingPathComponent("Info.plist").path], in: root)
    return app.path
  }

  /// FNV-1a over every byte, as `Data.hashValue` reads only a prefix.
  static func digest(_ contents: Data) -> String {
    String(contents.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }, radix: 16)
  }

  /// Every item under `path`, as the properties an install depends on.
  static func tree(at path: String, keepHardLinks: Bool = true, directoryTimes: Bool = true, linkTimes: Bool = false) throws -> [String: String] {
    let fileManager = FileManager.default
    var tree: [String: String] = [:]
    for relative in try fileManager.subpathsOfDirectory(atPath: path) {
      let item = (path as NSString).appendingPathComponent(relative)
      let attributes = try fileManager.attributesOfItem(atPath: item)
      let type = try #require(attributes[.type] as? FileAttributeType)
      let mode = String(try #require(attributes[.posixPermissions] as? Int), radix: 8)
      let modified = try #require(attributes[.modificationDate] as? Date).timeIntervalSince1970
      switch type {
      case .typeSymbolicLink:
        let destination = try fileManager.destinationOfSymbolicLink(atPath: item)
        tree[relative] = linkTimes ? "link \(destination) \(modified)" : "link \(destination)"
      case .typeDirectory:
        tree[relative] = directoryTimes ? "dir \(mode) \(modified)" : "dir \(mode)"
      default:
        let contents = try Data(contentsOf: URL(fileURLWithPath: item))
        let links = keepHardLinks ? " \(try #require(attributes[.referenceCount] as? Int))" : ""
        tree[relative] = "file \(mode) \(modified)\(links) \(contents.count) \(digest(contents))"
      }
    }
    return tree
  }

  /// What `bsdtar` extracts, less the AppleDouble entries for symlinks: `bsdtar` cannot apply metadata to a symlink, so it writes those entries out as files.
  static func bsdtarTree(at path: String, keepHardLinks: Bool = true, directoryTimes: Bool = true, linkTimes: Bool = false) throws -> [String: String] {
    try tree(at: path, keepHardLinks: keepHardLinks, directoryTimes: directoryTimes, linkTimes: linkTimes).filter { relative, _ in
      let name = (relative as NSString).lastPathComponent
      let sibling = ((relative as NSString).deletingLastPathComponent as NSString).appendingPathComponent(String(name.dropFirst(2)))
      return !(name.hasPrefix("._") && (try? FileManager.default.destinationOfSymbolicLink(atPath: "\(path)/\(sibling)")) != nil)
    }
  }

  static func differences(_ expected: [String: String], _ actual: [String: String]) -> String {
    Set(expected.keys).union(actual.keys).sorted().filter { expected[$0] != actual[$0] }.map { "\($0): \(expected[$0] ?? "-") vs \(actual[$0] ?? "-")" }.joined(separator: "\n")
  }
}

/// An extractor that records what reached it, and what its directory held at the time, so a test can tell an in-process extraction from a fallback.
final class RecordingExtractor: ArchiveExtractor {

  private let wrapped: (any ArchiveExtractor)?
  private let recorded = OSAllocatedUnfairLock<[(path: String?, existing: [String])]>(initialState: [])

  /// Records, then passes the archive on to `wrapped`, if any.
  init(_ wrapped: (any ArchiveExtractor)? = nil) {
    self.wrapped = wrapped
  }

  /// Each archive that reached this extractor, by path, or `nil` for a stream.
  var extractions: [(path: String?, existing: [String])] {
    recorded.withLock { $0 }
  }

  var wasReached: Bool {
    !extractions.isEmpty
  }

  func extract(fromFile path: String, to extractPath: String, options: ArchiveExtractOptions, logger: any ControlCoreLogger) async throws {
    let existing = try FileManager.default.contentsOfDirectory(atPath: extractPath)
    recorded.withLock { $0.append((path, existing)) }
    try await wrapped?.extract(fromFile: path, to: extractPath, options: options, logger: logger)
  }

  func extract(from source: any ByteSource, to extractPath: String, options: ArchiveExtractOptions, logger: any ControlCoreLogger) async throws {
    let existing = try FileManager.default.contentsOfDirectory(atPath: extractPath)
    recorded.withLock { $0.append((nil, existing)) }
    try await wrapped?.extract(from: source, to: extractPath, options: options, logger: logger)
  }
}
