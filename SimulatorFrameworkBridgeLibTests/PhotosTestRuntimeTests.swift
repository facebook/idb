/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@testable import SimulatorFrameworkBridgeRuntime
import XCTest

final class PhotosTestRuntimeTests: XCTestCase {

  // MARK: - run

  func testRunPropagatesClosureStatus() {
    let runtime = FBPhotosTestRuntime()

    let status = runtime.run { _ in 37 }

    XCTAssertEqual(status, 37)
  }

  func testRunBuildsClientWithConfiguredAssets() {
    let runtime = FBPhotosTestRuntime()
    runtime.assetCount = 3

    let status = runtime.run { client in
      client.deleteAssets() ? 0 : 1
    }

    XCTAssertEqual(status, 0)
    XCTAssertEqual(
      runtime.operations as NSArray,
      [
        "value:_lazyPhotoLibrary", "unwrap", "transactionBegin", "context",
        "id:asset0", "lookup:asset0", "delete:asset0",
        "id:asset1", "lookup:asset1", "delete:asset1",
        "id:asset2", "lookup:asset2", "delete:asset2",
        "save", "transactionEnd",
      ] as NSArray)
    XCTAssertTrue(runtime.allMutationsInsideTransaction)
  }

  func testRunReturnsAfterWorkerTransactionCompletes() {
    let runtime = FBPhotosTestRuntime()
    runtime.runTransactionsOnWorkerQueue = true

    let status = runtime.run { client in
      client.deleteAssets() ? 0 : 1
    }

    XCTAssertEqual(status, 0)
    XCTAssertTrue(runtime.transactionRanOnWorkerThread)
    XCTAssertEqual(runtime.operations.lastObject as? String, "transactionEnd")
    XCTAssertTrue(runtime.allMutationsInsideTransaction)
    XCTAssertNil(runtime.escapedTransactionException)
  }

  // MARK: - runCatchingException

  func testRunCatchingExceptionPackagesClosureStatus() {
    let runtime = FBPhotosTestRuntime()

    let result = runtime.runCatchingException { _ in 23 }

    XCTAssertEqual(result["status"] as? Int, 23)
    XCTAssertNil(result["exception"])
  }

  func testRunCatchingExceptionCapturesObjectiveCException() {
    let runtime = FBPhotosTestRuntime()

    let result = runtime.runCatchingException { client in
      client.setValue("value", forKey: "missingKey")
      return 0
    }

    XCTAssertEqual(
      result["exception"] as? String,
      NSExceptionName.undefinedKeyException.rawValue)
    XCTAssertNil(result["status"])
  }
}
