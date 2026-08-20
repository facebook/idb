/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBProcessIOFailureTests: XCTestCase {

  func testAttachViaFileDetachesSuccessfulOutputWhenPeerOutputFails() throws {
    let stdOut = RecordingProcessOutput(filePath: "/tmp/stdout")
    let expectedError = NSError(domain: "FBProcessIOTests", code: 7)
    let stdErr = RecordingProcessOutput(error: expectedError)
    let io = FBProcessIO<NSNull, NSNull, NSNull>(
      stdIn: nil,
      stdOut: stdOut,
      stdErr: stdErr
    )

    XCTAssertThrowsError(try io.attachViaFile().`await`()) { error in
      XCTAssertEqual((error as NSError).domain, expectedError.domain)
      XCTAssertEqual((error as NSError).code, expectedError.code)
    }
    XCTAssertEqual(stdOut.detachCallCount, 1)
  }
}

private final class RecordingProcessOutput: FBProcessOutput<NSNull> {

  let filePath: String
  let error: NSError?
  private(set) var detachCallCount = 0

  init(filePath: String) {
    self.filePath = filePath
    self.error = nil
    super.init()
  }

  init(error: NSError) {
    filePath = ""
    self.error = error
    super.init()
  }

  override func providedThroughFile() -> FBFuture<FBProcessFileOutput> {
    if let error {
      return FBFuture<FBProcessFileOutput>(error: error)
    }
    return FBFuture<FBProcessFileOutput>(result: RecordingProcessFileOutput(filePath: filePath))
  }

  override func detach() -> FBFuture<NSNull> {
    detachCallCount += 1
    return FBFuture<NSNull>.empty()
  }
}

private final class RecordingProcessFileOutput: NSObject, FBProcessFileOutput {

  let filePath: String

  init(filePath: String) {
    self.filePath = filePath
  }

  func startReading() -> FBFuture<NSNull> {
    return FBFuture<NSNull>.empty()
  }

  func stopReading() -> FBFuture<NSNull> {
    return FBFuture<NSNull>.empty()
  }
}
