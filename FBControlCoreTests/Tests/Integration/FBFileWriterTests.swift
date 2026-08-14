/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBFileWriterTests: XCTestCase {

  func testNonBlockingCloseOfPipe() throws {
    let pipe = Pipe()
    var writeError: NSError?
    guard let writer = FBFileWriter.asyncWriter(withFileDescriptor: pipe.fileHandleForWriting.fileDescriptor, closeOnEndOfFile: true, error: &writeError) else {
      throw writeError!
    }

    let expected = "Foo Bar Baz".data(using: .utf8)!
    writer.consumeData(expected)

    let actual = pipe.fileHandleForReading.availableData
    XCTAssertEqual(expected, actual)

    writer.consumeEndOfFile()
    try writer.finishedConsuming.`await`()

    pipe.fileHandleForWriting.closeFile()
    pipe.fileHandleForReading.closeFile()
  }

  func testNonBlockingClose() throws {
    let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
    XCTAssertTrue(FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil))
    let fileHandle = FileHandle(forWritingAtPath: filePath)
    XCTAssertNotNil(fileHandle)
    var writeError: NSError?
    guard let writer = FBFileWriter.asyncWriter(withFileDescriptor: fileHandle!.fileDescriptor, closeOnEndOfFile: true, error: &writeError) else {
      throw writeError!
    }

    let data = "Foo Bar Baz".data(using: .utf8)!
    writer.consumeData(data)
    writer.consumeEndOfFile()
  }

}
