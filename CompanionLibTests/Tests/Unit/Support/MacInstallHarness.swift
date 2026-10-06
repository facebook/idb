/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
@preconcurrency import FBControlCore
import Foundation
import XCTestBootstrap

/// An `IDBCommandExecutor` driving the host Mac, so installs run end to end through the companion's
/// storage without a simulator. Bundles are built under a scratch directory the harness owns.
final class MacInstallHarness {

  let target: MacDevice
  let executor: IDBCommandExecutor
  private let scratch: URL
  private let logger: any ControlCoreLogger

  init() throws {
    logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)
    target = MacDevice(logger: logger)
    scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MacInstallHarness-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    executor = IDBCommandExecutor.commandExecutor(
      forTarget: target,
      storageManager: try IDBStorageManager.manager(forTarget: target, logger: logger),
      temporaryDirectory: TemporaryDirectory(logger: logger),
      debugserverPort: 0,
      logger: IDBLogger(loggers: [logger])
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: scratch)
    try? FileManager.default.removeItem(atPath: target.auxillaryDirectory)
  }

  /// Writes a flat bundle in a directory of its own, with a host Mach-O as its executable because
  /// reading a bundle parses the binary's architectures.
  func makeBundle(named name: String, extension pathExtension: String, identifier: String) throws -> URL {
    let bundle = scratch.appendingPathComponent(UUID().uuidString).appendingPathComponent("\(name).\(pathExtension)")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: bundle.appendingPathComponent(name))
    let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": name, "CFBundleName": name]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
    return bundle
  }

  /// Writes a single file whose content is a host Mach-O, as a dylib would be.
  func makeFile(named name: String) throws -> URL {
    let file = scratch.appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: file)
    return file
  }

  /// A gzipped tar holding `item` and its siblings at its root, as clients stream bundles.
  func gzippedTar(of item: URL) async throws -> FBProcessInput<AnyObject> {
    FBProcessInput<NSData>(from: try await gzippedTarData(of: item)).retyped(FBProcessInput<AnyObject>.self)
  }

  func gzippedTarData(of item: URL) async throws -> Data {
    try await FBArchiveOperations.createGzippedTarData(forPath: item.deletingLastPathComponent().path, logger: logger)
  }

  /// An uncompressed tar holding `item` and its siblings at its root.
  func tar(of item: URL) throws -> FBProcessInput<AnyObject> {
    FBProcessInput<NSData>(from: try tarData(of: item)).retyped(FBProcessInput<AnyObject>.self)
  }

  func tarData(of item: URL) throws -> Data {
    try archive(extension: "tar") { ("/usr/bin/tar", ["-cf", $0.path, "-C", item.deletingLastPathComponent().path, "."]) }
  }

  /// A zip holding `item` at its root.
  func zipData(of item: URL) throws -> Data {
    try archive(extension: "zip") { ("/usr/bin/ditto", ["-c", "-k", "--keepParent", item.path, $0.path]) }
  }

  /// `data` in a zstd frame of uncompressed blocks, as the tests cannot rely on a zstd compressor being installed.
  static func zstd(_ data: Data) -> Data {
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

  /// Runs the command `writing` gives for an archive path, and reads the archive it writes there.
  private func archive(extension pathExtension: String, writing command: (URL) -> (tool: String, arguments: [String])) throws -> Data {
    let archive = scratch.appendingPathComponent("\(UUID().uuidString).\(pathExtension)")
    let (tool, arguments) = command(archive)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw ArchiveToolFailed(tool: tool, status: process.terminationStatus)
    }
    return try Data(contentsOf: archive)
  }

  /// `item` gzipped on its own, as clients stream single files.
  func gzipped(_ item: URL) async throws -> FBProcessInput<AnyObject> {
    let data = try await FBArchiveOperations.createGzipData(forPath: item.path, logger: logger)
    return FBProcessInput<NSData>(from: data).retyped(FBProcessInput<AnyObject>.self)
  }
}

private struct ArchiveToolFailed: Error, CustomStringConvertible {
  let tool: String
  let status: Int32

  var description: String { "\(tool) exited with status \(status)" }
}
