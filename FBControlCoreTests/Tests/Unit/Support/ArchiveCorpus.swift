/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing
import os

/// Archives of one app, written by every producer the system has, and the trees
/// extracting them leaves behind.
struct ArchiveCorpus {

  enum Producer: String, CaseIterable, CustomTestStringConvertible {
    case dittoZip
    case dittoZipWithResourceForks
    case zipDeflated
    case zipStored
    case zip64
    case zipToAPipe
    case tarGzip
    case tarUncompressed
    case tarGzipGNU
    case tarGzipUstar
    case tarGzipPax
    case tarGzipWithoutMacMetadata
    case tarGzipInTwoMembers

    var isZip: Bool {
      switch self {
      case .dittoZip, .dittoZipWithResourceForks, .zipDeflated, .zipStored, .zip64, .zipToAPipe:
        return true
      case .tarGzip, .tarUncompressed, .tarGzipGNU, .tarGzipUstar, .tarGzipPax, .tarGzipWithoutMacMetadata, .tarGzipInTwoMembers:
        return false
      }
    }

    /// A zip stores a hard link as a second copy, and some producers cannot store a symlink or an empty file.
    var keepsHardLinks: Bool { !isZip }

    var testDescription: String { rawValue }
  }

  let root: URL
  private let fileManager = FileManager.default

  init(root: URL) {
    self.root = root
  }

  func run(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.currentDirectoryURL = root
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "\(launchPath) \(arguments)")
  }

  /// An app with what installs meet: modes, file and directory symlinks, a framework with a `Versions/Current` link, a hard link, long, spaced and non-ASCII names, an extended attribute, empty files and directories, and contents that do and do not compress across many read buffers.
  @discardableResult
  func makeApp() throws -> URL {
    let app = root.appendingPathComponent("A.app")
    let long = "Real/" + String(repeating: "nested-directory/", count: 8) + "ünïcode file with a long name.txt"
    let framework = app.appendingPathComponent("Frameworks/F.framework")
    for directory in [(long as NSString).deletingLastPathComponent, "Private", "Empty", "Many"] {
      try fileManager.createDirectory(at: app.appendingPathComponent(directory), withIntermediateDirectories: true)
    }
    try fileManager.createDirectory(at: framework.appendingPathComponent("Versions/A/Resources"), withIntermediateDirectories: true)
    // Reading a bundle parses its executable's header.
    try fileManager.copyItem(atPath: "/bin/ls", toPath: app.appendingPathComponent("A").path)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("A").path)
    let plist: [String: Any] = ["CFBundleIdentifier": "com.example.corpus", "CFBundleName": "A", "CFBundleExecutable": "A", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
    try Data(String(repeating: "compressible ", count: 300_000).utf8).write(to: app.appendingPathComponent("big.txt"))
    var generator = SplitMix64(seed: 7)
    try Data((0..<1_500_000).map { _ in UInt8.random(in: .min ... .max, using: &generator) }).write(to: app.appendingPathComponent("random.bin"))
    try Data("long".utf8).write(to: app.appendingPathComponent(long))
    try Data().write(to: app.appendingPathComponent("Real/empty"))
    for index in 0..<200 {
      try Data("file \(index)".utf8).write(to: app.appendingPathComponent("Many/\(index).txt"))
    }
    try Data("secret".utf8).write(to: app.appendingPathComponent("Private/key"))
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: app.appendingPathComponent("Private/key").path)
    // Directories get explicit modes, as bsdtar masks what it extracts with its umask and the in-process extractors do not.
    for relative in try fileManager.subpathsOfDirectory(atPath: app.path) + [""] where try fileManager.attributesOfItem(atPath: app.appendingPathComponent(relative).path)[.type] as? FileAttributeType == .typeDirectory {
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent(relative).path)
    }
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: app.appendingPathComponent("Private").path)
    try Data("framework".utf8).write(to: framework.appendingPathComponent("Versions/A/F"))
    try Data("<plist/>".utf8).write(to: framework.appendingPathComponent("Versions/A/Resources/Info.plist"))
    try fileManager.createSymbolicLink(atPath: framework.appendingPathComponent("Versions/Current").path, withDestinationPath: "A")
    try fileManager.createSymbolicLink(atPath: framework.appendingPathComponent("F").path, withDestinationPath: "Versions/Current/F")
    try fileManager.createSymbolicLink(atPath: framework.appendingPathComponent("Resources").path, withDestinationPath: "Versions/Current/Resources")
    try fileManager.createSymbolicLink(atPath: app.appendingPathComponent("link.plist").path, withDestinationPath: "Info.plist")
    try fileManager.createSymbolicLink(atPath: app.appendingPathComponent("LinkDir").path, withDestinationPath: "Real")
    try fileManager.linkItem(atPath: app.appendingPathComponent("A").path, toPath: app.appendingPathComponent("Hardlink").path)
    try run("/usr/bin/xattr", ["-w", "com.example.tag", "value", app.appendingPathComponent("Info.plist").path])
    // A fixed time, so that a producer writes the same bytes on every run and mutations land on the same structures. Deepest first, as setting a child's time moves its directory's.
    let items = try fileManager.subpathsOfDirectory(atPath: app.path).sorted { $0.count > $1.count } + [""]
    for relative in items {
      try run("/usr/bin/touch", ["-h", "-t", "202311142213.20", app.appendingPathComponent(relative).path])
    }
    return app
  }

  /// Writes `A.app` under `root` as `producer` does, returning the archive.
  func archive(_ producer: Producer) throws -> URL {
    let archive = root.appendingPathComponent("A.\(producer.rawValue).\(producer.isZip ? "zip" : "tar")")
    let app = root.appendingPathComponent("A.app").path
    switch producer {
    case .dittoZip:
      try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive.path])
    case .dittoZipWithResourceForks:
      try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app, archive.path])
    case .zipDeflated:
      try run("/usr/bin/zip", ["-qry", archive.path, "A.app"])
    case .zipStored:
      try run("/usr/bin/zip", ["-qry0", archive.path, "A.app"])
    case .zip64:
      try run("/usr/bin/zip", ["-qry", "-fz", archive.path, "A.app"])
    case .zipToAPipe:
      // zip cannot seek back into a pipe, so it writes data descriptors; it follows symlinks there and cannot store an empty file.
      try run("/bin/sh", ["-c", "/usr/bin/zip -qr - A.app -x A.app/Real/empty A.app/LinkDir/empty | /bin/cat > \"$0\"", archive.path])
    case .tarGzip:
      try run("/usr/bin/tar", ["-czf", archive.path, "A.app"])
    case .tarUncompressed:
      try run("/usr/bin/tar", ["-cf", archive.path, "A.app"])
    case .tarGzipGNU:
      try run("/usr/bin/tar", ["--format", "gnutar", "-czf", archive.path, "A.app"])
    case .tarGzipUstar:
      try run("/usr/bin/tar", ["--format", "ustar", "-czf", archive.path, "A.app"])
    case .tarGzipPax:
      try run("/usr/bin/tar", ["--format", "pax", "-czf", archive.path, "A.app"])
    case .tarGzipWithoutMacMetadata:
      try run("/usr/bin/tar", ["--no-mac-metadata", "-czf", archive.path, "A.app"])
    case .tarGzipInTwoMembers:
      let tar = root.appendingPathComponent("two-members.tar")
      try run("/usr/bin/tar", ["-cf", tar.path, "A.app"])
      let contents = try Data(contentsOf: tar)
      let half = contents.count / 2
      try (try gzip(contents.prefix(half)) + gzip(contents.suffix(from: half))).write(to: archive)
    }
    return archive
  }

  private func gzip(_ data: Data) throws -> Data {
    let input = root.appendingPathComponent("member")
    try data.write(to: input)
    try run("/usr/bin/gzip", ["-nf", input.path])
    return try Data(contentsOf: root.appendingPathComponent("member.gz"))
  }

  /// Every item under `path`, as the properties an install depends on.
  /// FNV-1a over every byte, as `Data.hashValue` reads only a prefix.
  static func digest(_ contents: Data) -> String {
    String(contents.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }, radix: 16)
  }

  func tree(at path: String, keepHardLinks: Bool, directoryTimes: Bool = true) throws -> [String: String] {
    var tree: [String: String] = [:]
    for relative in try fileManager.subpathsOfDirectory(atPath: path) {
      let item = (path as NSString).appendingPathComponent(relative)
      let attributes = try fileManager.attributesOfItem(atPath: item)
      let type = try #require(attributes[.type] as? FileAttributeType)
      let mode = String(try #require(attributes[.posixPermissions] as? Int), radix: 8)
      let modified = try #require(attributes[.modificationDate] as? Date).timeIntervalSince1970
      switch type {
      case .typeSymbolicLink:
        tree[relative] = "link \(try fileManager.destinationOfSymbolicLink(atPath: item))"
      case .typeDirectory:
        tree[relative] = directoryTimes ? "dir \(mode) \(modified)" : "dir \(mode)"
      default:
        let contents = try Data(contentsOf: URL(fileURLWithPath: item))
        let links = keepHardLinks ? " \(try #require(attributes[.referenceCount] as? Int))" : ""
        tree[relative] = "file \(mode) \(modified)\(links) \(contents.count) \(Self.digest(contents))"
      }
    }
    return tree
  }

  /// What `bsdtar` extracts, less the AppleDouble entries for symlinks: `bsdtar` cannot apply metadata to a symlink, so it writes those entries out as files.
  func bsdtarTree(at path: String, keepHardLinks: Bool, directoryTimes: Bool = true) throws -> [String: String] {
    try tree(at: path, keepHardLinks: keepHardLinks, directoryTimes: directoryTimes).filter { relative, _ in
      let name = (relative as NSString).lastPathComponent
      let sibling = ((relative as NSString).deletingLastPathComponent as NSString).appendingPathComponent(String(name.dropFirst(2)))
      return !(name.hasPrefix("._") && (try? fileManager.destinationOfSymbolicLink(atPath: "\(path)/\(sibling)")) != nil)
    }
  }

  static func differences(_ expected: [String: String], _ actual: [String: String]) -> String {
    Set(expected.keys).union(actual.keys).sorted().filter { expected[$0] != actual[$0] }.map { "\($0): \(expected[$0] ?? "-") vs \(actual[$0] ?? "-")" }.joined(separator: "\n")
  }
}

/// An extractor that records being reached, so a test can tell an in-process extraction from a fallback.
final class RecordingExtractor: ArchiveExtractor {

  private let wrapped: any ArchiveExtractor
  private let reached = OSAllocatedUnfairLock(initialState: false)

  init(_ wrapped: any ArchiveExtractor) {
    self.wrapped = wrapped
  }

  var wasReached: Bool {
    reached.withLock { $0 }
  }

  func extract(_ source: ArchiveSource, to extractPath: String, options: ArchiveExtractOptions, logger: any ControlCoreLogger) async throws {
    reached.withLock { $0 = true }
    try await wrapped.extract(source, to: extractPath, options: options, logger: logger)
  }
}

/// A seeded generator, so that random contents and mutation offsets are the same on every run.
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

/// Serves each registered URL its body, so that tests running in parallel can each download their own archive.
final class CorpusURLProtocol: URLProtocol {

  private static let bodies = OSAllocatedUnfairLock(initialState: [URL: Data]())

  /// A URL that serves `body`.
  static func serving(_ body: Data) -> URL {
    // swiftlint:disable:next force_unwrapping
    let url = URL(string: "https://corpus.invalid/\(UUID().uuidString)")!
    bodies.withLock { $0[url] = body }
    return url
  }

  static var configuration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CorpusURLProtocol.self]
    return configuration
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url, let body = Self.bodies.withLock({ $0[url] }) else {
      client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
      return
    }
    // swiftlint:disable:next force_unwrapping
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(body.count)])!
    // Later, as the extractor attaches to the download only once extraction starts.
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(100)) {
      self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      var offset = 0
      while offset < body.count {
        self.client?.urlProtocol(self, didLoad: body.subdata(in: offset..<min(offset + 64 * 1024, body.count)))
        offset += 64 * 1024
      }
      self.client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}
}
