/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class BinaryDescriptorTests: XCTestCase {

  /// A fat system binary whose slices are `x86_64` and `arm64e`; `arm64e` reports as `arm64`.
  private static let fatBinary = "/bin/echo"

  /// A fat system binary carrying two `LC_RPATH` commands.
  private static let binaryWithRpaths = "/usr/bin/xprotect"

  private func temporaryFile(named name: String, contents: Data) throws -> String {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BinaryDescriptorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directory)
    }
    let path = directory.appendingPathComponent(name).path
    try contents.write(to: URL(fileURLWithPath: path))
    return path
  }

  func testFatBinary() throws {
    // xctest is a fat binary.
    let descriptor = try BinaryDescriptor.binary(withPath: ProcessInfo.processInfo.arguments.first!)
    XCTAssertNotNil(descriptor)
    XCTAssertNotNil(descriptor.uuid)

    let rpaths = try descriptor.rpaths()
    XCTAssertNotNil(rpaths)
  }

  func test64BitMacosCommand() throws {
    // codesign is not a fat binary.
    let descriptor = try BinaryDescriptor.binary(withPath: "/usr/bin/codesign")
    XCTAssertNotNil(descriptor)
    XCTAssertNotNil(descriptor.uuid)
  }

  // MARK: - Parsing

  func testFatBinaryYieldsEverySliceArchitecture() throws {
    try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.fatBinary))
    let descriptor = try BinaryDescriptor.binary(withPath: Self.fatBinary)
    XCTAssertEqual(Set(descriptor.architectures.map(\.rawValue)), ["x86_64", "arm64"])
    XCTAssertEqual(descriptor.name, "echo")
    XCTAssertEqual(descriptor.path, Self.fatBinary)
    XCTAssertNotNil(descriptor.uuid)
  }

  func testThinBinaryYieldsOneArchitecture() throws {
    let path = (XcodeConfiguration.developerDirectory as NSString).appendingPathComponent("usr/bin/xcodebuild")
    let descriptor = try BinaryDescriptor.binary(withPath: path)
    XCTAssertEqual(descriptor.architectures.count, 1)
    XCTAssertNotNil(descriptor.uuid)
  }

  func testRpathsAreReadFromTheLoadCommands() throws {
    try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.binaryWithRpaths))
    let descriptor = try BinaryDescriptor.binary(withPath: Self.binaryWithRpaths)
    XCTAssertEqual(try descriptor.rpaths(), ["@executable_path/../Frameworks", "@loader_path/../Frameworks"])
  }

  func testABinaryWithoutRpathsYieldsNone() throws {
    try XCTSkipUnless(FileManager.default.fileExists(atPath: "/usr/bin/codesign"))
    let descriptor = try BinaryDescriptor.binary(withPath: "/usr/bin/codesign")
    XCTAssertEqual(try descriptor.rpaths(), [])
  }

  // MARK: - Failures

  func testAMissingFileIsReported() {
    let path = "/var/empty/no-such-binary"
    XCTAssertThrowsError(try BinaryDescriptor.binary(withPath: path)) { error in
      XCTAssertEqual(error.localizedDescription, "Binary does not exist at path \(path)")
    }
  }

  func testAnUnreadableFileIsReported() throws {
    // Mode 0 does not stop root from reading.
    try XCTSkipIf(geteuid() == 0)
    let path = try temporaryFile(named: "unreadable", contents: Data([0xcf, 0xfa, 0xed, 0xfe]))
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
    XCTAssertThrowsError(try BinaryDescriptor.binary(withPath: path)) { error in
      XCTAssertEqual(error.localizedDescription, "Could not fopen file at path \(path)")
    }
  }

  func testAFileWithoutMachOMagicIsReported() throws {
    let path = try temporaryFile(named: "text", contents: Data("not a mach-o binary".utf8))
    XCTAssertThrowsError(try BinaryDescriptor.binary(withPath: path)) { error in
      XCTAssertTrue(error.localizedDescription.hasPrefix("Could not interpret magic "), error.localizedDescription)
      XCTAssertTrue(error.localizedDescription.hasSuffix(" in file \(path)"), error.localizedDescription)
    }
  }

  func testRpathsOfAFileWithoutMachOMagicAreReported() throws {
    let path = try temporaryFile(named: "text", contents: Data("not a mach-o binary".utf8))
    let descriptor = BinaryDescriptor(name: "text", architectures: [], uuid: nil, path: path)
    XCTAssertThrowsError(try descriptor.rpaths()) { error in
      XCTAssertTrue(error.localizedDescription.hasPrefix("Could not interpret magic "), error.localizedDescription)
    }
  }

  // MARK: - Value semantics

  func testEqualityIgnoresTheUUID() {
    let first = BinaryDescriptor(name: "tool", architectures: [BinaryArchitecture(rawValue: "arm64")], uuid: UUID(), path: "/usr/bin/tool")
    let second = BinaryDescriptor(name: "tool", architectures: [BinaryArchitecture(rawValue: "arm64")], uuid: UUID(), path: "/usr/bin/tool")
    XCTAssertEqual(first, second)
    XCTAssertEqual(first.hashValue, second.hashValue)
  }

  func testInequalityByArchitectures() {
    let first = BinaryDescriptor(name: "tool", architectures: [BinaryArchitecture(rawValue: "arm64")], uuid: nil, path: "/usr/bin/tool")
    let second = BinaryDescriptor(name: "tool", architectures: [BinaryArchitecture(rawValue: "x86_64")], uuid: nil, path: "/usr/bin/tool")
    XCTAssertNotEqual(first, second)
  }

  func testArchitecturesEncodeAsPlainStrings() throws {
    let encoded = try JSONEncoder().encode([BinaryArchitecture.arm64, BinaryArchitecture(rawValue: "x86_64")])
    XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"["arm64","x86_64"]"#)
    XCTAssertEqual(try JSONDecoder().decode([BinaryArchitecture].self, from: encoded), [.arm64, .x86_64])
  }

  func testDescriptionNamesThePathAndArchitectures() {
    let descriptor = BinaryDescriptor(name: "tool", architectures: [BinaryArchitecture(rawValue: "arm64")], uuid: nil, path: "/usr/bin/tool")
    XCTAssertEqual(descriptor.description, "Name: tool | Path: /usr/bin/tool | Architectures: [arm64]")
  }
}
