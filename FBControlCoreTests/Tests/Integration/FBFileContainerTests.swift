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
  private func setUpBasePathContainer() -> any FBFileContainerProtocol {
    let fm = FileManager.default
    try! fm.createDirectory(atPath: basePath, withIntermediateDirectories: true, attributes: nil)
    try! fm.createDirectory(atPath: directoryInBasePath, withIntermediateDirectories: true, attributes: nil)
    try! (fileInBasePathText as NSString).write(toFile: fileInBasePath, atomically: true, encoding: String.Encoding.utf8.rawValue)
    try! (fileInDirectoryInBasePathText as NSString).write(toFile: fileInDirectoryInBasePath, atomically: true, encoding: String.Encoding.utf8.rawValue)
    return FBFileContainer.fileContainer(forBasePath: basePath) as! any FBFileContainerProtocol
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
  private func setUpMappedPathContainer() -> any FBFileContainerProtocol {
    let fm = FileManager.default
    try! fm.createDirectory(atPath: fooPath, withIntermediateDirectories: true, attributes: nil)
    try! fm.createDirectory(atPath: barPath, withIntermediateDirectories: true, attributes: nil)
    try! fm.createDirectory(atPath: directoryInBar, withIntermediateDirectories: true, attributes: nil)
    try! (fileInFooText as NSString).write(toFile: fileInFoo, atomically: true, encoding: String.Encoding.utf8.rawValue)
    try! (fileInDirectoryInBarText as NSString).write(toFile: fileInDirectoryInBar, atomically: true, encoding: String.Encoding.utf8.rawValue)
    let pathMapping: [String: String] = ["foo": fooPath, "bar": barPath]
    return FBFileContainer.fileContainer(forPathMapping: pathMapping) as! any FBFileContainerProtocol
  }

  // MARK: - Base Path Tests

  func testBasePathDirectoryListingAtRoot() throws {
    let container = setUpBasePathContainer()
    let expectedFiles: Set<String> = ["file.txt", "dir"]
    let actualFiles = try container.contents(ofDirectory: ".").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathDirectoryListingAtSubdirectory() throws {
    let container = setUpBasePathContainer()
    let expectedFiles: Set<String> = ["some.txt"]
    let actualFiles = try container.contents(ofDirectory: "dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    // Listing a dir that doesn't exist fails.
    XCTAssertNil(try? container.contents(ofDirectory: "no_dir").`await`())
  }

  func testBasePathPullFile() throws {
    let container = setUpBasePathContainer()
    var pulledFile = try container.copy(fromContainer: "file.txt", toHost: basePathPulledFileTestBasePath).`await`() as String
    pulledFile = (pulledFile as NSString).appendingPathComponent("file.txt")
    let actualContent = try String(contentsOfFile: pulledFile, encoding: .utf8)
    XCTAssertEqual(actualContent, fileInBasePathText)
  }

  func testBasePathPullFileFromDirectory() throws {
    let container = setUpBasePathContainer()
    var pulledFile = try container.copy(fromContainer: "dir/some.txt", toHost: basePathPulledFileTestBasePath).`await`() as String
    pulledFile = (pulledFile as NSString).appendingPathComponent("some.txt")
    let actualContent = try String(contentsOfFile: pulledFile, encoding: .utf8)
    XCTAssertEqual(actualContent, fileInDirectoryInBasePathText)
  }

  func testBasePathPullEntireDirectory() throws {
    let container = setUpBasePathContainer()
    let pulledDirectory = try container.copy(fromContainer: "dir", toHost: basePathPulledDirectoryTestBasePath).`await`() as String
    let expectedFiles: Set<String> = ["some.txt"]
    let actualFiles = try FileManager.default.contentsOfDirectory(atPath: pulledDirectory)
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathCreateDirectory() throws {
    let container = setUpBasePathContainer()
    let _: NSNull = try container.createDirectory("other").`await`()
    var expectedFiles: Set<String> = ["file.txt", "dir", "other"]
    var actualFiles = try container.contents(ofDirectory: ".").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    let _: NSNull = try container.createDirectory("other/nested/here").`await`()
    expectedFiles = ["nested"]
    actualFiles = try container.contents(ofDirectory: "other").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    expectedFiles = ["here"]
    actualFiles = try container.contents(ofDirectory: "other/nested").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathPushFile() throws {
    let container = setUpBasePathContainer()
    let pushedFile = TestFixtures.photo0Path
    let _: NSNull = try container.copy(fromHost: pushedFile, toContainer: "dir").`await`()
    let expectedFiles: Set<String> = ["some.txt", "photo0.png"]
    let actualFiles = try container.contents(ofDirectory: "dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathPushDirectory() throws {
    let container = setUpBasePathContainer()
    let pushedDirectory = (TestFixtures.photo0Path as NSString).deletingLastPathComponent
    let _: NSNull = try container.copy(fromHost: pushedDirectory, toContainer: "dir").`await`()
    var expectedFiles: Set<String> = ["some.txt", "Resources"]
    var actualFiles = try container.contents(ofDirectory: "dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    expectedFiles = [
      "xctest",
      "app_custom_set.crash",
      "tree.json",
      "app_default_set.crash",
      "assetsd_custom_set.crash",
      "xctest-concated-json-crash.ips",
      "agent_custom_set.crash",
      "photo0.png",
      "simulator_system.log",
    ]
    actualFiles = try container.contents(ofDirectory: "dir/Resources").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathMoveFile() throws {
    let container = setUpBasePathContainer()
    let _: NSNull = try container.move(from: "file.txt", to: "dir/file.txt").`await`()
    let expectedFiles: Set<String> = ["some.txt", "file.txt"]
    let actualFiles = try container.contents(ofDirectory: "dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testBasePathMoveDirectory() throws {
    let container = setUpBasePathContainer()
    let _: NSNull = try container.move(from: "dir", to: "moved_dir").`await`()
    var expectedFiles: Set<String> = ["some.txt"]
    var actualFiles = try container.contents(ofDirectory: "moved_dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    XCTAssertNil(try? container.contents(ofDirectory: "dir").`await`())
    // Then back again.
    let _: NSNull = try container.move(from: "moved_dir", to: "dir").`await`()
    expectedFiles = ["some.txt"]
    actualFiles = try container.contents(ofDirectory: "dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    XCTAssertNil(try? container.contents(ofDirectory: "moved_dir").`await`())
  }

  func testBasePathDeleteFile() throws {
    let container = setUpBasePathContainer()
    let _: NSNull = try container.remove("dir/some.txt").`await`()
    let expectedFiles: Set<String> = []
    let actualFiles = try container.contents(ofDirectory: "dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    let _: NSNull = try container.remove("dir").`await`()
    XCTAssertNil(try? container.contents(ofDirectory: "dir").`await`())
  }

  // MARK: - Mapped Path Tests

  func testMappedPathDirectoryListingAtRoot() throws {
    let container = setUpMappedPathContainer()
    let expectedFiles: Set<String> = ["foo", "bar"]
    let actualFiles = try container.contents(ofDirectory: ".").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathDirectoryListingInsideMapping() throws {
    let container = setUpMappedPathContainer()
    var expectedFiles: Set<String> = ["file.txt"]
    var actualFiles = try container.contents(ofDirectory: "foo").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    expectedFiles = ["dir"]
    actualFiles = try container.contents(ofDirectory: "bar").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    expectedFiles = ["in_dir.txt"]
    actualFiles = try container.contents(ofDirectory: "bar/dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathDirectoryListingOfNonExistentDirectory() throws {
    let container = setUpMappedPathContainer()
    XCTAssertNil(try? container.contents(ofDirectory: "no_dir").`await`())
  }

  func testMappedPathPullFile() throws {
    let container = setUpMappedPathContainer()
    var pulledFile = try container.copy(fromContainer: "foo/file.txt", toHost: basePathPulledFileTestPathMapping).`await`() as String
    pulledFile = (pulledFile as NSString).appendingPathComponent("file.txt")
    let actualContent = try String(contentsOfFile: pulledFile, encoding: .utf8)
    XCTAssertEqual(actualContent, fileInFooText)
  }

  func testMappedPathPullFileInMappedDirectory() throws {
    let container = setUpMappedPathContainer()
    var pulledFile = try container.copy(fromContainer: "bar/dir/in_dir.txt", toHost: basePathPulledFileTestPathMapping).`await`() as String
    pulledFile = (pulledFile as NSString).appendingPathComponent("in_dir.txt")
    let actualContent = try String(contentsOfFile: pulledFile, encoding: .utf8)
    XCTAssertEqual(actualContent, fileInDirectoryInBarText)
  }

  func testMappedPathPullDirectory() throws {
    let container = setUpMappedPathContainer()
    let pulledDirectory = try container.copy(fromContainer: "bar/dir", toHost: basePathPulledDirectoryTestPathMapping).`await`() as String
    let expectedFiles: Set<String> = ["in_dir.txt"]
    let actualFiles = try FileManager.default.contentsOfDirectory(atPath: pulledDirectory)
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathPullRootPath() throws {
    let container = setUpMappedPathContainer()
    let pulledDirectory = try container.copy(fromContainer: "bar", toHost: basePathPulledMappedDirectoryTestPathMapping).`await`() as String
    let expectedFiles: Set<String> = ["dir"]
    let actualFiles = try FileManager.default.contentsOfDirectory(atPath: pulledDirectory)
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathCreateDirectoryInContainer() throws {
    let container = setUpMappedPathContainer()
    let _: NSNull = try container.createDirectory("foo/other").`await`()
    var actualFiles = try container.contents(ofDirectory: "foo").`await`() as! [String]
    XCTAssertNotNil(actualFiles)
    let _: NSNull = try container.createDirectory("foo/other/nested/here").`await`()
    actualFiles = try container.contents(ofDirectory: "foo/other").`await`() as! [String]
    XCTAssertNotNil(actualFiles)
    actualFiles = try container.contents(ofDirectory: "foo/other/nested").`await`() as! [String]
    XCTAssertNotNil(actualFiles)
  }

  func testMappedPathCreateDirectoryAtRootFails() throws {
    let container = setUpMappedPathContainer()
    XCTAssertNil(try? container.createDirectory("no_create").`await`())
  }

  func testMappedPathPushFile() throws {
    let container = setUpMappedPathContainer()
    let pushedFile = TestFixtures.photo0Path
    let _: NSNull = try container.copy(fromHost: pushedFile, toContainer: "bar/dir").`await`()
    let expectedFiles: Set<String> = ["in_dir.txt", "photo0.png"]
    let actualFiles = try container.contents(ofDirectory: "bar/dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathPushDirectory() throws {
    let container = setUpMappedPathContainer()
    let pushedDirectory = (TestFixtures.photo0Path as NSString).deletingLastPathComponent
    let _: NSNull = try container.copy(fromHost: pushedDirectory, toContainer: "bar/dir").`await`()
    var expectedFiles: Set<String> = ["in_dir.txt", "Resources"]
    var actualFiles = try container.contents(ofDirectory: "bar/dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    expectedFiles = [
      "xctest",
      "app_custom_set.crash",
      "tree.json",
      "app_default_set.crash",
      "assetsd_custom_set.crash",
      "xctest-concated-json-crash.ips",
      "agent_custom_set.crash",
      "photo0.png",
      "simulator_system.log",
    ]
    actualFiles = try container.contents(ofDirectory: "bar/dir/Resources").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathPushToRootFails() throws {
    let container = setUpMappedPathContainer()
    let pushedFile = TestFixtures.photo0Path
    XCTAssertNil(try? container.copy(fromHost: pushedFile, toContainer: ".").`await`())
  }

  func testMappedPathMoveFile() throws {
    let container = setUpMappedPathContainer()
    let _: NSNull = try container.move(from: "foo/file.txt", to: "bar/dir/file.txt").`await`()
    let expectedFiles: Set<String> = ["in_dir.txt", "file.txt"]
    let actualFiles = try container.contents(ofDirectory: "bar/dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathMoveDirectory() throws {
    let container = setUpMappedPathContainer()
    let _: NSNull = try container.move(from: "bar/dir", to: "bar/moved_dir").`await`()
    var expectedFiles: Set<String> = ["in_dir.txt"]
    var actualFiles = try container.contents(ofDirectory: "bar/moved_dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    XCTAssertNil(try? container.contents(ofDirectory: "bar/dir").`await`())
    // Then back again.
    let _: NSNull = try container.move(from: "bar/moved_dir", to: "bar/dir").`await`()
    expectedFiles = ["in_dir.txt"]
    actualFiles = try container.contents(ofDirectory: "bar/dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
    XCTAssertNil(try? container.contents(ofDirectory: "bar/moved_dir").`await`())
  }

  func testMappedPathDeleteFile() throws {
    let container = setUpMappedPathContainer()
    let _: NSNull = try container.remove("bar/dir/in_dir.txt").`await`()
    let expectedFiles: Set<String> = []
    let actualFiles = try container.contents(ofDirectory: "bar/dir").`await`() as! [String]
    XCTAssertEqual(expectedFiles, Set(actualFiles))
  }

  func testMappedPathDeleteDirectory() throws {
    let container = setUpMappedPathContainer()
    let _: NSNull = try container.remove("bar/dir").`await`()
    XCTAssertNil(try? container.contents(ofDirectory: "bar/dir").`await`())
    // Deleting a root fails
    XCTAssertNil(try? container.remove(".").`await`())
  }
}
// swiftlint:enable force_cast
