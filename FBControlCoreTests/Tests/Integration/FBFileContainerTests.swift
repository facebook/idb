/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

// swiftlint:disable force_cast
final class FBFileContainerTests: XCTestCase {

  private var basePathTestBasePath: String!
  private var basePathPulledFileTestBasePath: String!
  private var basePathPulledDirectoryTestBasePath: String!
  private var basePathTestPathMappingFoo: String!
  private var basePathTestPathMappingBar: String!
  private var basePathPulledFileTestPathMapping: String!
  private var basePathPulledDirectoryTestPathMapping: String!
  private var basePathPulledMappedDirectoryTestPathMapping: String!

  override func setUp() {
    super.setUp()
    basePathTestBasePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString)_FBSimulatorFileCommandsTests_testBasePath")
    basePathPulledFileTestBasePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString)_FBSimulatorFileCommandsTests_testBasePath_pulled_file")
    basePathPulledDirectoryTestBasePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString)_FBSimulatorFileCommandsTests_testBasePath_pulled_directory")
    basePathTestPathMappingFoo = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString)_FBSimulatorFileCommandsTests_testPathMapping_foo")
    basePathTestPathMappingBar = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString)_FBSimulatorFileCommandsTests_testPathMapping_bar")
    basePathPulledFileTestPathMapping = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString)_FBSimulatorFileCommandsTests_testPathMapping_pulled_file")
    basePathPulledDirectoryTestPathMapping = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString)_FBSimulatorFileCommandsTests_testPathMapping_pulled_directory")
    basePathPulledMappedDirectoryTestPathMapping = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString)_FBSimulatorFileCommandsTests_testPathMapping_pulled_mapped_directory")
  }

  override func tearDown() {
    super.tearDown()
    let fm = FileManager.default
    for path in [basePathTestBasePath!, basePathPulledFileTestBasePath!, basePathPulledDirectoryTestBasePath!, basePathTestPathMappingFoo!, basePathTestPathMappingBar!, basePathPulledFileTestPathMapping!, basePathPulledDirectoryTestPathMapping!, basePathPulledMappedDirectoryTestPathMapping!] {
      try? fm.removeItem(atPath: path)
    }
  }

  // MARK: - Base Path Helpers

  private var basePath: String { basePathTestBasePath }
  private var fileInBasePath: String { (basePath as NSString).appendingPathComponent("file.txt") }
  private var directoryInBasePath: String { (basePath as NSString).appendingPathComponent("dir") }
  private var fileInDirectoryInBasePath: String { (directoryInBasePath as NSString).appendingPathComponent("some.txt") }

  private let fileInBasePathText = "Some Text"
  private let fileInDirectoryInBasePathText = "Other Text"

  @discardableResult
  private func setUpBasePathContainer() throws -> any AsyncFileContainer {
    let fm = FileManager.default
    try fm.createDirectory(atPath: basePath, withIntermediateDirectories: true, attributes: nil)
    try fm.createDirectory(atPath: directoryInBasePath, withIntermediateDirectories: true, attributes: nil)
    try (fileInBasePathText as NSString).write(toFile: fileInBasePath, atomically: true, encoding: String.Encoding.utf8.rawValue)
    try (fileInDirectoryInBasePathText as NSString).write(toFile: fileInDirectoryInBasePath, atomically: true, encoding: String.Encoding.utf8.rawValue)
    return FBFileContainer.fileContainer(forBasePath: basePath) as! any AsyncFileContainer
  }

  // MARK: - Mapped Path Helpers

  private var fooPath: String { basePathTestPathMappingFoo }
  private var fileInFoo: String { (fooPath as NSString).appendingPathComponent("file.txt") }
  private var barPath: String { basePathTestPathMappingBar }
  private var directoryInBar: String { (barPath as NSString).appendingPathComponent("dir") }
  private var fileInDirectoryInBar: String { (directoryInBar as NSString).appendingPathComponent("in_dir.txt") }

  private let fileInFooText = "Some Text"
  private let fileInDirectoryInBarText = "Other Text"

  @discardableResult
  private func setUpMappedPathContainer() throws -> any AsyncFileContainer {
    let fm = FileManager.default
    try fm.createDirectory(atPath: fooPath, withIntermediateDirectories: true, attributes: nil)
    try fm.createDirectory(atPath: barPath, withIntermediateDirectories: true, attributes: nil)
    try fm.createDirectory(atPath: directoryInBar, withIntermediateDirectories: true, attributes: nil)
    try (fileInFooText as NSString).write(toFile: fileInFoo, atomically: true, encoding: String.Encoding.utf8.rawValue)
    try (fileInDirectoryInBarText as NSString).write(toFile: fileInDirectoryInBar, atomically: true, encoding: String.Encoding.utf8.rawValue)
    let pathMapping: [String: String] = ["foo": fooPath, "bar": barPath]
    return FBFileContainer.fileContainer(forPathMapping: pathMapping) as! any AsyncFileContainer
  }

  // MARK: - Base Path Tests

  func testBasePathDirectoryListingAtRoot() async throws {
    let container = try setUpBasePathContainer()
    let expectedFiles: Set<String> = ["file.txt", "dir"]
    let actualFiles = try await container.contents(ofDirectory: ".")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathDirectoryListingAtSubdirectory() async throws {
    let container = try setUpBasePathContainer()
    let expectedFiles: Set<String> = ["some.txt"]
    let actualFiles = try await container.contents(ofDirectory: "dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    // Listing a dir that doesn't exist fails.
    let missing = try? await container.contents(ofDirectory: "no_dir")
    XCTAssertNil(missing)
  }

  func testBasePathPullFile() async throws {
    let container = try setUpBasePathContainer()
    var pulledFile = try await container.copy(fromContainer: "file.txt", toHost: basePathPulledFileTestBasePath)
    pulledFile = (pulledFile as NSString).appendingPathComponent("file.txt")
    let actualContent = try String(contentsOfFile: pulledFile, encoding: .utf8)
    XCTAssertEqual(actualContent, fileInBasePathText)
  }

  func testBasePathPullFileFromDirectory() async throws {
    let container = try setUpBasePathContainer()
    var pulledFile = try await container.copy(fromContainer: "dir/some.txt", toHost: basePathPulledFileTestBasePath)
    pulledFile = (pulledFile as NSString).appendingPathComponent("some.txt")
    let actualContent = try String(contentsOfFile: pulledFile, encoding: .utf8)
    XCTAssertEqual(actualContent, fileInDirectoryInBasePathText)
  }

  func testBasePathPullEntireDirectory() async throws {
    let container = try setUpBasePathContainer()
    let pulledDirectory = try await container.copy(fromContainer: "dir", toHost: basePathPulledDirectoryTestBasePath)
    let expectedFiles: Set<String> = ["some.txt"]
    let actualFiles = try FileManager.default.contentsOfDirectory(atPath: pulledDirectory)
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathCreateDirectory() async throws {
    let container = try setUpBasePathContainer()
    try await container.createDirectory("other")
    var expectedFiles: Set<String> = ["file.txt", "dir", "other"]
    var actualFiles = try await container.contents(ofDirectory: ".")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    try await container.createDirectory("other/nested/here")
    expectedFiles = ["nested"]
    actualFiles = try await container.contents(ofDirectory: "other")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    expectedFiles = ["here"]
    actualFiles = try await container.contents(ofDirectory: "other/nested")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathPushFile() async throws {
    let container = try setUpBasePathContainer()
    let pushedFile = TestFixtures.photo0Path
    try await container.copy(fromHost: pushedFile, toContainer: "dir")
    let expectedFiles: Set<String> = ["some.txt", "photo0.png"]
    let actualFiles = try await container.contents(ofDirectory: "dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathPushDirectory() async throws {
    let container = try setUpBasePathContainer()
    let pushedDirectory = (TestFixtures.photo0Path as NSString).deletingLastPathComponent
    try await container.copy(fromHost: pushedDirectory, toContainer: "dir")
    var expectedFiles: Set<String> = ["some.txt", "Resources"]
    var actualFiles = try await container.contents(ofDirectory: "dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    expectedFiles = [
      "app_custom_set.crash",
      "tree.json",
      "app_default_set.crash",
      "assetsd_custom_set.crash",
      "xctest-concated-json-crash.ips",
      "agent_custom_set.crash",
      "photo0.png",
      "simulator_system.log",
    ]
    actualFiles = try await container.contents(ofDirectory: "dir/Resources")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathMoveFile() async throws {
    let container = try setUpBasePathContainer()
    try await container.move(from: "file.txt", to: "dir/file.txt")
    let expectedFiles: Set<String> = ["some.txt", "file.txt"]
    let actualFiles = try await container.contents(ofDirectory: "dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathMoveDirectory() async throws {
    let container = try setUpBasePathContainer()
    try await container.move(from: "dir", to: "moved_dir")
    var expectedFiles: Set<String> = ["some.txt"]
    var actualFiles = try await container.contents(ofDirectory: "moved_dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    let missing = try? await container.contents(ofDirectory: "dir")
    XCTAssertNil(missing)
    // Then back again.
    try await container.move(from: "moved_dir", to: "dir")
    expectedFiles = ["some.txt"]
    actualFiles = try await container.contents(ofDirectory: "dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    let missingMoved = try? await container.contents(ofDirectory: "moved_dir")
    XCTAssertNil(missingMoved)
  }

  func testBasePathDeleteFile() async throws {
    let container = try setUpBasePathContainer()
    try await container.remove("dir/some.txt")
    let expectedFiles: Set<String> = []
    let actualFiles = try await container.contents(ofDirectory: "dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    try await container.remove("dir")
    let missing = try? await container.contents(ofDirectory: "dir")
    XCTAssertNil(missing)
  }

  // MARK: - Mapped Path Tests

  func testMappedPathDirectoryListingAtRoot() async throws {
    let container = try setUpMappedPathContainer()
    let expectedFiles: Set<String> = ["foo", "bar"]
    let actualFiles = try await container.contents(ofDirectory: ".")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathDirectoryListingInsideMapping() async throws {
    let container = try setUpMappedPathContainer()
    var expectedFiles: Set<String> = ["file.txt"]
    var actualFiles = try await container.contents(ofDirectory: "foo")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    expectedFiles = ["dir"]
    actualFiles = try await container.contents(ofDirectory: "bar")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    expectedFiles = ["in_dir.txt"]
    actualFiles = try await container.contents(ofDirectory: "bar/dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathDirectoryListingOfNonExistentDirectory() async throws {
    let container = try setUpMappedPathContainer()
    let missing = try? await container.contents(ofDirectory: "no_dir")
    XCTAssertNil(missing)
  }

  func testMappedPathPullFile() async throws {
    let container = try setUpMappedPathContainer()
    var pulledFile = try await container.copy(fromContainer: "foo/file.txt", toHost: basePathPulledFileTestPathMapping)
    pulledFile = (pulledFile as NSString).appendingPathComponent("file.txt")
    let actualContent = try String(contentsOfFile: pulledFile, encoding: .utf8)
    XCTAssertEqual(actualContent, fileInFooText)
  }

  func testMappedPathPullFileInMappedDirectory() async throws {
    let container = try setUpMappedPathContainer()
    var pulledFile = try await container.copy(fromContainer: "bar/dir/in_dir.txt", toHost: basePathPulledFileTestPathMapping)
    pulledFile = (pulledFile as NSString).appendingPathComponent("in_dir.txt")
    let actualContent = try String(contentsOfFile: pulledFile, encoding: .utf8)
    XCTAssertEqual(actualContent, fileInDirectoryInBarText)
  }

  func testMappedPathPullDirectory() async throws {
    let container = try setUpMappedPathContainer()
    let pulledDirectory = try await container.copy(fromContainer: "bar/dir", toHost: basePathPulledDirectoryTestPathMapping)
    let expectedFiles: Set<String> = ["in_dir.txt"]
    let actualFiles = try FileManager.default.contentsOfDirectory(atPath: pulledDirectory)
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathPullRootPath() async throws {
    let container = try setUpMappedPathContainer()
    let pulledDirectory = try await container.copy(fromContainer: "bar", toHost: basePathPulledMappedDirectoryTestPathMapping)
    let expectedFiles: Set<String> = ["dir"]
    let actualFiles = try FileManager.default.contentsOfDirectory(atPath: pulledDirectory)
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathCreateDirectoryInContainer() async throws {
    let container = try setUpMappedPathContainer()
    try await container.createDirectory("foo/other")
    var actualFiles = try await container.contents(ofDirectory: "foo")
    XCTAssertNotNil(actualFiles)
    try await container.createDirectory("foo/other/nested/here")
    actualFiles = try await container.contents(ofDirectory: "foo/other")
    XCTAssertNotNil(actualFiles)
    actualFiles = try await container.contents(ofDirectory: "foo/other/nested")
    XCTAssertNotNil(actualFiles)
  }

  func testMappedPathCreateDirectoryAtRootFails() async throws {
    let container = try setUpMappedPathContainer()
    let result: Void? = try? await container.createDirectory("no_create")
    XCTAssertNil(result)
  }

  func testMappedPathPushFile() async throws {
    let container = try setUpMappedPathContainer()
    let pushedFile = TestFixtures.photo0Path
    try await container.copy(fromHost: pushedFile, toContainer: "bar/dir")
    let expectedFiles: Set<String> = ["in_dir.txt", "photo0.png"]
    let actualFiles = try await container.contents(ofDirectory: "bar/dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathPushDirectory() async throws {
    let container = try setUpMappedPathContainer()
    let pushedDirectory = (TestFixtures.photo0Path as NSString).deletingLastPathComponent
    try await container.copy(fromHost: pushedDirectory, toContainer: "bar/dir")
    var expectedFiles: Set<String> = ["in_dir.txt", "Resources"]
    var actualFiles = try await container.contents(ofDirectory: "bar/dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    expectedFiles = [
      "app_custom_set.crash",
      "tree.json",
      "app_default_set.crash",
      "assetsd_custom_set.crash",
      "xctest-concated-json-crash.ips",
      "agent_custom_set.crash",
      "photo0.png",
      "simulator_system.log",
    ]
    actualFiles = try await container.contents(ofDirectory: "bar/dir/Resources")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathPushToRootFails() async throws {
    let container = try setUpMappedPathContainer()
    let pushedFile = TestFixtures.photo0Path
    let result: Void? = try? await container.copy(fromHost: pushedFile, toContainer: ".")
    XCTAssertNil(result)
  }

  func testMappedPathMoveFile() async throws {
    let container = try setUpMappedPathContainer()
    try await container.move(from: "foo/file.txt", to: "bar/dir/file.txt")
    let expectedFiles: Set<String> = ["in_dir.txt", "file.txt"]
    let actualFiles = try await container.contents(ofDirectory: "bar/dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathMoveDirectory() async throws {
    let container = try setUpMappedPathContainer()
    try await container.move(from: "bar/dir", to: "bar/moved_dir")
    var expectedFiles: Set<String> = ["in_dir.txt"]
    var actualFiles = try await container.contents(ofDirectory: "bar/moved_dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    let missing = try? await container.contents(ofDirectory: "bar/dir")
    XCTAssertNil(missing)
    // Then back again.
    try await container.move(from: "bar/moved_dir", to: "bar/dir")
    expectedFiles = ["in_dir.txt"]
    actualFiles = try await container.contents(ofDirectory: "bar/dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    let missingMoved = try? await container.contents(ofDirectory: "bar/moved_dir")
    XCTAssertNil(missingMoved)
  }

  func testMappedPathDeleteFile() async throws {
    let container = try setUpMappedPathContainer()
    try await container.remove("bar/dir/in_dir.txt")
    let expectedFiles: Set<String> = []
    let actualFiles = try await container.contents(ofDirectory: "bar/dir")
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathDeleteDirectory() async throws {
    let container = try setUpMappedPathContainer()
    try await container.remove("bar/dir")
    let missing = try? await container.contents(ofDirectory: "bar/dir")
    XCTAssertNil(missing)
    // Deleting a root fails
    let rootResult: Void? = try? await container.remove(".")
    XCTAssertNil(rootResult)
  }
}
// swiftlint:enable force_cast
