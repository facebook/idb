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
    let data =
      try FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath(BSDTarPath, arguments: ["-zc", "-f", "-", "-C", item.deletingLastPathComponent().path, "."])
      .withStdErr(toLoggerAndErrorMessage: logger)
      .withStdOutInMemoryAsData()
      .runUntilCompletion(withAcceptableExitCodes: [0])
      .`await`().stdOut ?? NSData()
    return data as Data
  }

  /// An uncompressed tar holding `item` and its siblings at its root.
  func tar(of item: URL) throws -> FBProcessInput<AnyObject> {
    let archive = scratch.appendingPathComponent("\(UUID().uuidString).tar")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = ["-cf", archive.path, "-C", item.deletingLastPathComponent().path, "."]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw ArchiveToolFailed(tool: "tar", status: process.terminationStatus)
    }
    return FBProcessInput<NSData>(from: try Data(contentsOf: archive)).retyped(FBProcessInput<AnyObject>.self)
  }

  /// `item` gzipped on its own, as clients stream single files.
  func gzipped(_ item: URL) async throws -> FBProcessInput<AnyObject> {
    let data =
      try FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/gzip", arguments: ["--to-stdout", item.path])
      .withStdErr(toLoggerAndErrorMessage: logger)
      .withStdOutInMemoryAsData()
      .runUntilCompletion(withAcceptableExitCodes: [0])
      .`await`().stdOut ?? NSData()
    return FBProcessInput<NSData>(from: data as Data).retyped(FBProcessInput<AnyObject>.self)
  }
}

private struct ArchiveToolFailed: Error, CustomStringConvertible {
  let tool: String
  let status: Int32

  var description: String { "\(tool) exited with status \(status)" }
}
