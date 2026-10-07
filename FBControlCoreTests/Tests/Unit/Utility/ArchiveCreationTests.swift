/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest

/// One member of a tar, after any pax extended header has been applied to it.
private struct TarEntry {
  let path: String
  let type: Character
  let mode: Int
  let modificationTime: Int
  let linkTarget: String
  let contents: Data
  let extendedAttributes: [String]

  /// bsdtar writes an AppleDouble `._name` member ahead of anything carrying macOS metadata.
  var isAppleDouble: Bool {
    (path as NSString).lastPathComponent.hasPrefix("._")
  }
}

/// The members of a gzipped tar, decompressed and parsed independently of the code under test.
private func tarEntries(_ gzipped: Data) throws -> [TarEntry] {
  // gzip exits 2 for a warning, as the zero padding bsdtar writes after the gzip stream raises.
  let tar = try runTool("/usr/bin/gzip", ["-dc"], input: gzipped, succeedingWith: [0, 2])
  var entries: [TarEntry] = []
  var extended: [String: String] = [:]
  var extendedAttributes: [String] = []
  var offset = 0
  while offset + 512 <= tar.count {
    let header = tar.subdata(in: offset..<offset + 512)
    if header.allSatisfy({ $0 == 0 }) {
      break
    }
    let type = Character(UnicodeScalar(header[156]))
    let size = type == "x" ? octal(header, 124..<136) : extended["size"].flatMap { Int($0) } ?? octal(header, 124..<136)
    let body = tar.subdata(in: offset + 512..<offset + 512 + size)
    offset += 512 + (size + 511) / 512 * 512
    if type == "x" {
      for (key, value) in paxRecords(body) {
        if key.hasPrefix("SCHILY.xattr.") {
          extendedAttributes.append(String(key.dropFirst("SCHILY.xattr.".count)))
        } else {
          extended[key] = value
        }
      }
      continue
    }
    let name = string(header, 0..<100)
    let prefix = string(header, 345..<500)
    entries.append(
      TarEntry(
        path: extended["path"] ?? (prefix.isEmpty ? name : "\(prefix)/\(name)"),
        type: type,
        mode: octal(header, 100..<108) & 0o7777,
        modificationTime: extended["mtime"].flatMap { Double($0) }.map { Int($0) } ?? octal(header, 136..<148),
        linkTarget: extended["linkpath"] ?? string(header, 157..<257),
        contents: body,
        extendedAttributes: extendedAttributes))
    extended = [:]
    extendedAttributes = []
  }
  return entries
}

private func string(_ header: Data, _ range: Range<Int>) -> String {
  let field = header[range]
  return String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
}

private func octal(_ header: Data, _ range: Range<Int>) -> Int {
  Int(string(header, range).trimmingCharacters(in: .whitespaces), radix: 8) ?? 0
}

/// pax records are `<length> <key>=<value>\n`, where the length counts the whole record.
private func paxRecords(_ body: Data) -> [(String, String)] {
  let bytes = [UInt8](body)
  var records: [(String, String)] = []
  var start = 0
  while start < bytes.count, let space = bytes[start...].firstIndex(of: UInt8(ascii: " ")),
    let length = Int(String(decoding: bytes[start..<space], as: UTF8.self)), length > 0
  {
    let record = bytes[(space + 1)..<(start + length - 1)]
    if let equals = record.firstIndex(of: UInt8(ascii: "=")) {
      records.append((String(decoding: record[..<equals], as: UTF8.self), String(decoding: record[(equals + 1)...], as: UTF8.self)))
    }
    start += length
  }
  return records
}

/// Runs a system tool with `input` as a file argument, returning its standard output.
private func runTool(_ executable: String, _ arguments: [String], input: Data? = nil, succeedingWith statuses: Set<Int32> = [0]) throws -> Data {
  var arguments = arguments
  var inputFile: URL?
  if let input {
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try input.write(to: file)
    arguments.append(file.path)
    inputFile = file
  }
  defer { inputFile.map { try? FileManager.default.removeItem(at: $0) } }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  let output = Pipe()
  process.standardOutput = output
  try process.run()
  let data = output.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard statuses.contains(process.terminationStatus) else {
    throw NSError(domain: "ArchiveCreationTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\(executable) \(arguments) exited \(process.terminationStatus)"])
  }
  return data
}

/// Pins what the archives the companion sends contain: the entries, their types, modes, link targets and contents, so
/// that a different encoder produces archives every client already extracts the same way.
final class ArchiveCreationTests: XCTestCase {

  private static let modificationTime = Date(timeIntervalSince1970: 1_600_000_000)
  private static let longDirectory = String(repeating: "d", count: 70)
  private static let longFile = String(repeating: "f", count: 60)
  private static let longTarget = String(repeating: "t", count: 120)

  private var logger: ControlCoreLoggerDouble!
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    logger = ControlCoreLoggerDouble()
    tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    super.tearDown()
  }

  /// A tree with every kind of entry an app bundle or trace can hold, including names too long for a plain ustar header.
  private func makeTree() throws -> URL {
    let fileManager = FileManager.default
    let root = tempDirectory.appendingPathComponent("root")
    try fileManager.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: root.appendingPathComponent(Self.longDirectory), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: root.appendingPathComponent("bin/tool"))
    try Data("alpha".utf8).write(to: root.appendingPathComponent("a.txt"))
    try Data("long".utf8).write(to: root.appendingPathComponent("\(Self.longDirectory)/\(Self.longFile)"))
    try fileManager.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: "a.txt")
    try fileManager.createSymbolicLink(atPath: root.appendingPathComponent("longlink").path, withDestinationPath: Self.longTarget)
    try fileManager.linkItem(at: root.appendingPathComponent("a.txt"), to: root.appendingPathComponent("hard"))
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
    try fileManager.setAttributes([.posixPermissions: 0o750], ofItemAtPath: root.appendingPathComponent("bin").path)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("bin/tool").path)
    try fileManager.setAttributes(
      [.posixPermissions: 0o644, .modificationDate: Self.modificationTime],
      ofItemAtPath: root.appendingPathComponent("a.txt").path)
    return root
  }

  func testADirectoryIsArchivedWithItselfAsTheRoot() async throws {
    let root = try makeTree()

    let entries = try tarEntries(try await FBArchiveOperations.createGzippedTarData(forPath: root.path, logger: logger)).filter { !$0.isAppleDouble }
    let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

    let long = "./\(Self.longDirectory)/\(Self.longFile)"
    XCTAssertEqual(
      Set(byPath.keys),
      ["./", "./bin/", "./bin/tool", "./a.txt", "./hard", "./link", "./longlink", "./empty/", "./\(Self.longDirectory)/", long])
    XCTAssertEqual(entries.count, byPath.count, "no entry should be archived twice")

    XCTAssertEqual(byPath["./"]?.type, "5")
    XCTAssertEqual(byPath["./"]?.mode, 0o755)
    XCTAssertEqual(byPath["./bin/"]?.type, "5")
    XCTAssertEqual(byPath["./bin/"]?.mode, 0o750)
    XCTAssertEqual(byPath["./empty/"]?.type, "5")
    XCTAssertEqual(byPath["./bin/tool"]?.type, "0")
    XCTAssertEqual(byPath["./bin/tool"]?.mode, 0o755)
    XCTAssertEqual(byPath["./bin/tool"]?.contents, Data("#!/bin/sh\n".utf8))
    XCTAssertEqual(byPath[long]?.type, "0")
    XCTAssertEqual(byPath[long]?.contents, Data("long".utf8))
    XCTAssertEqual(byPath["./link"]?.type, "2")
    XCTAssertEqual(byPath["./link"]?.linkTarget, "a.txt")
    XCTAssertEqual(byPath["./longlink"]?.type, "2")
    XCTAssertEqual(byPath["./longlink"]?.linkTarget, Self.longTarget)

    // Which of a hardlinked pair carries the contents depends on directory order, not on the names.
    let pair = [byPath["./a.txt"], byPath["./hard"]].compactMap { $0 }
    let regular = try XCTUnwrap(pair.first { $0.type == "0" })
    let hardlink = try XCTUnwrap(pair.first { $0.type == "1" })
    XCTAssertEqual(hardlink.linkTarget, regular.path)
    XCTAssertEqual(regular.contents, Data("alpha".utf8))
    XCTAssertEqual(regular.mode, 0o644)
    XCTAssertEqual(regular.modificationTime, 1_600_000_000)
  }

  func testAFileIsArchivedByItsNameAlone() async throws {
    let file = tempDirectory.appendingPathComponent("single.txt")
    try Data("only".utf8).write(to: file)

    let entries = try tarEntries(try await FBArchiveOperations.createGzippedTarData(forPath: file.path, logger: logger)).filter { !$0.isAppleDouble }

    XCTAssertEqual(entries.map(\.path), ["single.txt"])
    XCTAssertEqual(entries.first?.type, "0")
    XCTAssertEqual(entries.first?.contents, Data("only".utf8))
  }

  func testAnEmptyDirectoryArchivesOnlyItsRoot() async throws {
    let entries = try tarEntries(try await FBArchiveOperations.createGzippedTarData(forPath: tempDirectory.path, logger: logger)).filter { !$0.isAppleDouble }

    XCTAssertEqual(entries.map(\.path), ["./"])
  }

  func testAnArchiveExtractsBackToTheSameTree() async throws {
    let root = try makeTree()
    let archive = try await FBArchiveOperations.createGzippedTarData(forPath: root.path, logger: logger)
    let destination = tempDirectory.appendingPathComponent("extracted")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

    _ = try runTool("/usr/bin/tar", ["-xp", "-C", destination.path, "-f"], input: archive)

    let fileManager = FileManager.default
    let path = { (relative: String) in destination.appendingPathComponent(relative).path }
    XCTAssertEqual(fileManager.contents(atPath: path("a.txt")), Data("alpha".utf8))
    XCTAssertEqual(fileManager.contents(atPath: path("\(Self.longDirectory)/\(Self.longFile)")), Data("long".utf8))
    XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: path("link")), "a.txt")
    XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: path("longlink")), Self.longTarget)
    XCTAssertEqual(try fileManager.attributesOfItem(atPath: path("bin"))[.posixPermissions] as? Int, 0o750)
    XCTAssertEqual(try fileManager.attributesOfItem(atPath: path("bin/tool"))[.posixPermissions] as? Int, 0o755)
    XCTAssertEqual(try fileManager.attributesOfItem(atPath: path("a.txt"))[.modificationDate] as? Date, Self.modificationTime)
    XCTAssertEqual(
      try fileManager.attributesOfItem(atPath: path("hard"))[.systemFileNumber] as? Int,
      try fileManager.attributesOfItem(atPath: path("a.txt"))[.systemFileNumber] as? Int)
    XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: path("empty")), [])
  }

  func testBothArchiveKindsAreGzipFromAUnixHost() async throws {
    let file = tempDirectory.appendingPathComponent("payload")
    try Data((0..<(256 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: file)

    let gzipped = try await FBArchiveOperations.createGzipData(forPath: file.path, logger: logger)
    let tarred = try await FBArchiveOperations.createGzippedTarData(forPath: file.path, logger: logger)

    for data in [gzipped, tarred] {
      XCTAssertEqual(Array(data.prefix(3)), [0x1F, 0x8B, 0x08], "gzip magic and deflate")
      XCTAssertEqual(data[9], 3, "the OS byte names a Unix host")
    }
    XCTAssertEqual(try runTool("/usr/bin/gzip", ["-dc"], input: gzipped), try Data(contentsOf: file))
  }

  func testATarArchiveEndsAtTheGzipTrailer() async throws {
    let file = tempDirectory.appendingPathComponent("payload")
    try Data("padded".utf8).write(to: file)

    let tarred = try await FBArchiveOperations.createGzippedTarData(forPath: file.path, logger: logger)

    XCTAssertNoThrow(try runTool("/usr/bin/gzip", ["-t"], input: tarred))
  }

  func testExtendedAttributesAreNotArchived() async throws {
    let file = tempDirectory.appendingPathComponent("a.txt")
    try Data("alpha".utf8).write(to: file)
    let value = Data("pinned".utf8)
    let status = value.withUnsafeBytes { setxattr(file.path, "com.example.pin", $0.baseAddress, value.count, 0, 0) }
    XCTAssertEqual(status, 0)

    let entries = try tarEntries(try await FBArchiveOperations.createGzippedTarData(forPath: tempDirectory.path, logger: logger))

    XCTAssertEqual(entries.map(\.path), ["./", "./a.txt"])
    XCTAssertEqual(entries.first { $0.path == "./a.txt" }?.extendedAttributes, [])
  }
}
