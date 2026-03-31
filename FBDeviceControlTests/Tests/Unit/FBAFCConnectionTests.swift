// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
import FBDeviceControl
import XCTest

// MARK: - File-scope state for C function pointer callbacks

private var sFileOffset: Int64 = 0
private var sFileMode: UInt64 = 0
private var sEvents: [String: NSMutableArray] = [:]
private var sVirtualizedFilesAndAttributes: [String: [String: String]]?

private let DirCreateKey = "dirCreate"
private let FileCloseKey = "fileClose"
private let FileOpenKey = "fileRefOpen"
private let RemovePathKey = "removePath"
private let RenamePathKey = "renamePath"
private let FileContentsKey = "contents"

private let FooFileContents = "FooContents"

// MARK: - Helper functions for callbacks

private func appendPathToEvent(_ eventName: String, _ path: UnsafePointer<CChar>) {
  let events = sEvents[eventName]
  events?.add(String(cString: path))
}

private func appendPathsToEvent(_ eventName: String, _ first: UnsafePointer<CChar>, _ second: UnsafePointer<CChar>) {
  let events = sEvents[eventName]
  events?.add([String(cString: first), String(cString: second)])
}

private func contentsOfVirtualizedDirectory(_ directory: String) -> [String] {
  guard let virtualFiles = sVirtualizedFilesAndAttributes else { return [] }
  var contents: [String] = []
  for path in virtualFiles.keys {
    if path == directory {
      continue
    }
    let pathComponents = (path as NSString).pathComponents
    let isRootDirectory = directory.isEmpty || directory == "/"
    if isRootDirectory && pathComponents.count == 1 {
      contents.append((path as NSString).lastPathComponent)
    } else if !isRootDirectory && path.hasPrefix(directory) {
      contents.append((path as NSString).lastPathComponent)
    }
  }
  return contents
}

// MARK: - Test class

final class FBAFCConnectionTests: XCTestCase {

  private var rootHostDirectory: String = ""
  private var fooHostFilePath: String = ""
  private var barHostDirectory: String = ""
  private var bazHostFilePath: String = ""

  override func setUp() {
    super.setUp()

    sEvents = [:]
    sEvents[DirCreateKey] = NSMutableArray()
    sEvents[FileCloseKey] = NSMutableArray()
    sEvents[FileOpenKey] = NSMutableArray()
    sEvents[RemovePathKey] = NSMutableArray()
    sEvents[RenamePathKey] = NSMutableArray()
    sVirtualizedFilesAndAttributes = nil

    rootHostDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString)_FBAFCConnectionTests")
    fooHostFilePath = (rootHostDirectory as NSString).appendingPathComponent("foo.txt")
    barHostDirectory = (rootHostDirectory as NSString).appendingPathComponent("bar")
    bazHostFilePath = (barHostDirectory as NSString).appendingPathComponent("baz.empty")
  }

  override func tearDown() {
    super.tearDown()

    try? FileManager.default.removeItem(atPath: bazHostFilePath)
    try? FileManager.default.removeItem(atPath: barHostDirectory)
    try? FileManager.default.removeItem(atPath: fooHostFilePath)
    try? FileManager.default.removeItem(atPath: rootHostDirectory)
  }

  private var events: [String: [Any]] {
    var result: [String: [Any]] = [:]
    for (key, value) in sEvents {
      result[key] = value as! [Any]
    }
    return result
  }

  private func addVirtualizedRemoteFiles() {
    sVirtualizedFilesAndAttributes = [
      "remote_foo.txt": [FileContentsKey: "some foo"],
      "remote_empty": [FileContentsKey: ""],
      "remote_bar": ["st_ifmt": "S_IFDIR"],
      "remote_bar/some.txt": [FileContentsKey: "more nested text"],
      "remote_bar/other.txt": [FileContentsKey: "more other text"],
    ]
  }

  private func setUpConnection() -> FBAFCConnection {
    var afcCalls = AFCCalls()

    afcCalls.ConnectionCopyLastErrorInfo = { _ in
      return Unmanaged.passRetained(NSDictionary() as CFDictionary)
    }

    afcCalls.ConnectionProcessOperation = { _, _ in
      return 0
    }

    afcCalls.DirectoryClose = { _, _ in
      return 0
    }

    afcCalls.DirectoryCreate = { _, dir in
      appendPathToEvent(DirCreateKey, dir!)
      return 0
    }

    afcCalls.DirectoryOpen = { _, path, directoryOut in
      let pathString = String(cString: path!)
      let pathsToEnumerate = NSMutableArray(array: contentsOfVirtualizedDirectory(pathString))
      if pathsToEnumerate.count == 0 {
        return 1
      }
      if let directoryOut {
        directoryOut.pointee = Unmanaged<AnyObject>.passRetained(pathsToEnumerate)
      }
      return 0
    }

    afcCalls.DirectoryRead = { _, dir, directoryEntry in
      let pathsToEnumerate = unsafeBitCast(dir, to: NSMutableArray.self)
      if pathsToEnumerate.count == 0 {
        return 0
      }
      let next = pathsToEnumerate[0] as! NSString
      if let directoryEntry {
        directoryEntry.pointee = UnsafeMutablePointer(mutating: next.utf8String)
      }
      pathsToEnumerate.removeObject(at: 0)
      return 0
    }

    afcCalls.ErrorString = { _ in
      let str = ("some error" as NSString).utf8String!
      return UnsafeMutablePointer(mutating: str)
    }

    afcCalls.FileRefClose = { _, ref in
      let fileName = unsafeBitCast(ref, to: NSString.self)
      appendPathToEvent(FileCloseKey, fileName.utf8String!)
      return 0
    }

    afcCalls.FileRefOpen = { _, path, _, fileRefOut in
      if sVirtualizedFilesAndAttributes != nil {
        let filePath = String(cString: path)
        let fileContents = sVirtualizedFilesAndAttributes?[filePath]?[FileContentsKey]
        if fileContents == nil {
          return 1
        }
      }
      appendPathToEvent(FileOpenKey, path)
      let cfStr = CFStringCreateWithCString(nil, path, CFStringBuiltInEncodings.UTF8.rawValue)!
      fileRefOut.pointee = Unmanaged<AnyObject>.passRetained(cfStr)
      return 0
    }

    afcCalls.FileRefSeek = { _, fileRef, offset, mode in
      let filePath = unsafeBitCast(fileRef, to: NSString.self) as String
      let fileContents = sVirtualizedFilesAndAttributes?[filePath]?[FileContentsKey]
      if fileContents == nil {
        return 1
      }
      sFileOffset = offset
      sFileMode = mode
      return 0
    }

    afcCalls.FileRefTell = { _, fileRef, offsetOut in
      let filePath = unsafeBitCast(fileRef, to: NSString.self) as String
      let fileContents = sVirtualizedFilesAndAttributes?[filePath]?[FileContentsKey]
      guard let fileContents else {
        return 1
      }
      let fileData = fileContents.data(using: .ascii)!
      offsetOut.pointee = UInt64(fileData.count)
      return 0
    }

    afcCalls.FileRefRead = { _, fileRef, buffer, lengthOut in
      let filePath = unsafeBitCast(fileRef, to: NSString.self) as String
      let fileContents = sVirtualizedFilesAndAttributes?[filePath]?[FileContentsKey]
      guard let fileContents else {
        return 1
      }
      let fileData = fileContents.data(using: .ascii)!
      fileData.withUnsafeBytes { bytes in
        memcpy(buffer, bytes.baseAddress, fileData.count)
      }
      return 0
    }

    afcCalls.FileRefWrite = { _, _, _, _ in
      return 0
    }

    afcCalls.RenamePath = { _, src, dst in
      appendPathsToEvent(RenamePathKey, src, dst)
      return 0
    }

    afcCalls.RemovePath = { _, path in
      appendPathToEvent(RemovePathKey, path)
      return 0
    }

    afcCalls.OperationCreateRemovePathAndContents = { _, path, _ in
      if let path {
        let bridged = path as NSString
        appendPathToEvent(RemovePathKey, bridged.utf8String!)
      }
      return Unmanaged.passRetained("empty" as AnyObject)
    }

    afcCalls.OperationGetResultStatus = { _ in
      return 0
    }

    afcCalls.OperationGetResultObject = { _ in
      return Unmanaged.passRetained(NSDictionary() as AnyObject)
    }

    // Structure:
    // ./foo.txt
    // ./bar
    // ./bar/baz.empty
    try! FileManager.default.createDirectory(atPath: rootHostDirectory, withIntermediateDirectories: true, attributes: nil)
    try! FileManager.default.createDirectory(atPath: barHostDirectory, withIntermediateDirectories: true, attributes: nil)
    try! (FooFileContents as NSString).write(toFile: fooHostFilePath, atomically: true, encoding: String.Encoding.ascii.rawValue)
    FileManager.default.createFile(atPath: bazHostFilePath, contents: Data(), attributes: nil)

    return FBAFCConnection(connection: NSNull(), calls: afcCalls, logger: nil)
  }

  private func assertExpectedDirectoryCreate(_ expectedDirectoryCreate: [String]) {
    XCTAssertEqual(sEvents[DirCreateKey] as! [String]? ?? [], expectedDirectoryCreate)
  }

  private func assertExpectedFiles(_ expectedFiles: [String]) {
    XCTAssertEqual(sEvents[FileOpenKey] as! [String]? ?? [], expectedFiles)
    XCTAssertEqual(sEvents[FileCloseKey] as! [String]? ?? [], expectedFiles)
  }

  private func assertRenameFiles(_ expectedRenameFiles: [[String]]) {
    let actual = sEvents[RenamePathKey] as? [[String]] ?? []
    XCTAssertEqual(actual, expectedRenameFiles)
  }

  private func assertRemoveFiles(_ expectedRemoveFiles: [String]) {
    XCTAssertEqual(sEvents[RemovePathKey] as! [String]? ?? [], expectedRemoveFiles)
  }

  // MARK: - Tests

  func testRootDirectoryList() throws {
    let connection = setUpConnection()
    addVirtualizedRemoteFiles()
    let actual = try connection.contents(ofDirectory: "")
    let expected: Set<String> = ["remote_foo.txt", "remote_empty", "remote_bar"]
    XCTAssertEqual(Set(actual), expected)
  }

  func testNestedDirectoryList() throws {
    let connection = setUpConnection()
    addVirtualizedRemoteFiles()
    let actual = try connection.contents(ofDirectory: "remote_bar")
    let expected: Set<String> = ["some.txt", "other.txt"]
    XCTAssertEqual(Set(actual), expected)
  }

  func testMissingDirectoryFail() {
    let connection = setUpConnection()
    addVirtualizedRemoteFiles()
    XCTAssertThrowsError(try connection.contents(ofDirectory: "aaaaaa"))
  }

  func testReadsFile() throws {
    let connection = setUpConnection()
    addVirtualizedRemoteFiles()
    let expected = "some foo".data(using: .ascii)
    let actual = try connection.contents(ofPath: "remote_foo.txt")
    XCTAssertEqual(expected, actual)
  }

  func testFailsToReadDirectory() {
    let connection = setUpConnection()
    addVirtualizedRemoteFiles()
    XCTAssertThrowsError(try connection.contents(ofPath: "remote_bar"))
  }

  func testFailsToReadMissingFile() {
    let connection = setUpConnection()
    addVirtualizedRemoteFiles()
    XCTAssertThrowsError(try connection.contents(ofPath: "nope"))
  }

  func testCopySingleFileToRoot() throws {
    let connection = setUpConnection()
    try connection.copy(fromHost: fooHostFilePath, toContainerPath: "")

    assertExpectedDirectoryCreate([])
    assertExpectedFiles([
      "foo.txt"
    ])
  }

  func testCopyFileToContainerPath() throws {
    let connection = setUpConnection()
    try connection.copy(fromHost: fooHostFilePath, toContainerPath: "bing")

    assertExpectedDirectoryCreate([])
    assertExpectedFiles([
      "bing/foo.txt"
    ])
  }

  func testCopyItemsFromHostDirectory() throws {
    let connection = setUpConnection()
    try connection.copy(fromHost: rootHostDirectory, toContainerPath: "")

    let dirName = (rootHostDirectory as NSString).lastPathComponent
    assertExpectedDirectoryCreate([
      dirName,
      (dirName as NSString).appendingPathComponent("bar"),
    ])
    assertExpectedFiles([
      (dirName as NSString).appendingPathComponent("foo.txt"),
      (dirName as NSString).appendingPathComponent("bar/baz.empty"),
    ])
  }

  func testCreateDirectoryAtRoot() throws {
    let connection = setUpConnection()
    try connection.createDirectory("bing")

    assertExpectedDirectoryCreate(["bing"])
  }

  func testCreateDirectoryInsideDirectory() throws {
    let connection = setUpConnection()
    try connection.createDirectory("bar/bing")

    assertExpectedDirectoryCreate(["bar/bing"])
  }

  func testRenamePath() throws {
    let connection = setUpConnection()
    try connection.renamePath("foo.txt", destination: "bar.txt")

    assertRenameFiles([["foo.txt", "bar.txt"]])
  }

  func testRemovePath() throws {
    let connection = setUpConnection()
    try connection.removePath("foo.txt", recursively: true)

    assertRemoveFiles(["foo.txt"])
  }
}
