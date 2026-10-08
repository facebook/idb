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

@Suite
struct TarSourceTests {

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let fileManager = FileManager.default

  /// Each entry `bsdtar` lists in `tar`, by name, as the type character `ls -l` gives it.
  private func listing(_ tar: Data) throws -> [String: Character] {
    let archive = root.appendingPathComponent("\(UUID().uuidString).tar")
    try tar.write(to: archive)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: BSDTarPath)
    process.arguments = ["-tvf", archive.path]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let listed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
    return Dictionary(
      uniqueKeysWithValues: listed.split(separator: "\n").map { line in
        let fields = line.split(separator: " ")
        return (String(fields[fields.count - 1]), fields[0].first ?? "?")
      })
  }

  @Test
  func aSymlinkToADirectoryIsArchivedAsTheDirectory() throws {
    try fileManager.createDirectory(at: root.appendingPathComponent("real"), withIntermediateDirectories: true)
    try Data("a".utf8).write(to: root.appendingPathComponent("real/a"))
    let link = root.appendingPathComponent("link").path
    try fileManager.createSymbolicLink(atPath: link, withDestinationPath: "real")

    #expect(try listing(TarSource(path: link).readAll()) == ["./": "d", "./a": "-"])
  }

  @Test
  func aFIFOIsArchivedAndASocketIsSkipped() throws {
    // A socket's path has to fit `sun_path`, which a temporary directory's need not.
    let directory = URL(fileURLWithPath: "/tmp").appendingPathComponent(String(UUID().uuidString.prefix(8)))
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: directory) }
    try Data("file".utf8).write(to: directory.appendingPathComponent("file"))
    #expect(mkfifo(directory.appendingPathComponent("fifo").path, 0o644) == 0)
    let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(socketDescriptor) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: directory.appendingPathComponent("socket").path.utf8) }
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    try #require(bound == 0)

    #expect(try listing(TarSource(path: directory.path).readAll()) == ["./": "d", "./file": "-", "./fifo": "p"])
  }

  @Test
  func aFileThatShrinksWhileItIsReadFails() throws {
    let file = root.appendingPathComponent("shrinking")
    try Data(repeating: 1, count: 1 << 20).write(to: file)
    let source = TarSource(path: file.path)
    var header = [UInt8](repeating: 0, count: 512)
    #expect(try header.withUnsafeMutableBytes { try source.read(into: $0) } == 512)
    #expect(truncate(file.path, 10) == 0)

    do {
      _ = try source.readAll()
      Issue.record("archiving a file that shrank should fail")
    } catch ArchiveCreationError.fileChangedWhileArchiving(let path) {
      #expect(path == file.path)
    }
  }

  @Test
  func anUnreadableDirectoryIsNamed() throws {
    let directory = root.appendingPathComponent("tree/locked")
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
    defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
    guard !fileManager.isReadableFile(atPath: directory.path) else {
      // Permissions do not restrict this user.
      return
    }

    do {
      _ = try TarSource(path: root.appendingPathComponent("tree").path).readAll()
      Issue.record("archiving an unreadable directory should fail")
    } catch ArchiveCreationError.unreadable(let path, let reason) {
      #expect(path == directory.path)
      #expect(reason == "Permission denied")
    }
  }
}
