/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest

final class PhotoLibraryMutationTests: XCTestCase {
  func testEmptyLibraryDoesNotAccessPrivateStorage() {
    let runtime = FBPhotosTestRuntime()
    runtime.assetCount = 0
    XCTAssertEqual(runtime.run(), 0)
    XCTAssertEqual(runtime.operations.count, 0)
  }

  func testDeletesEveryAssetAndSavesInsideOneTransaction() {
    for succeeds in [true, false] {
      let runtime = FBPhotosTestRuntime()
      runtime.saveSucceeds = succeeds
      XCTAssertEqual(runtime.run(), succeeds ? 0 : 1)
      XCTAssertEqual(
        runtime.operations as NSArray,
        [
          "value:_lazyPhotoLibrary", "unwrap", "transactionBegin", "context",
          "id:asset0", "lookup:asset0", "delete:asset0", "id:asset1", "lookup:asset1", "delete:asset1",
          "save", "transactionEnd",
        ] as NSArray)
      XCTAssertTrue(runtime.allMutationsInsideTransaction)
    }
  }

  func testUnavailablePrivateLibraryStopsBeforeTransaction() {
    for (failure, expected) in [
      ("lazyException", ["value:_lazyPhotoLibrary"]),
      ("unwrapException", ["value:_lazyPhotoLibrary", "unwrap"]),
      ("libraryMissing", ["value:_lazyPhotoLibrary", "unwrap"]),
    ] {
      let runtime = FBPhotosTestRuntime()
      runtime.failure = failure
      XCTAssertEqual(runtime.run(), 1)
      XCTAssertEqual(runtime.operations as NSArray, expected as NSArray)
    }
  }

  func testMissingObjectsAndExceptionsStopTheTransactionWithoutSaving() {
    let prefix = ["value:_lazyPhotoLibrary", "unwrap", "transactionBegin", "context"]
    for (failure, body) in [
      ("contextException", []), ("contextMissing", []),
      ("idMissing", ["id:asset0"]),
      ("objectMissing", ["id:asset0", "lookup:asset0"]),
      ("lookupException", ["id:asset0", "lookup:asset0"]),
      ("deleteException", ["id:asset0", "lookup:asset0", "delete:asset0"]),
    ] {
      let runtime = FBPhotosTestRuntime()
      runtime.failure = failure
      XCTAssertEqual(runtime.run(), 1)
      XCTAssertEqual(runtime.operations as NSArray, (prefix + body + ["transactionEnd"]) as NSArray)
      XCTAssertTrue(runtime.allMutationsInsideTransaction)
    }
  }
  func testPrivateExceptionsAtCommandBoundary() {
    for failure in ["transactionException", "idException", "saveException"] {
      let runtime = FBPhotosTestRuntime()
      runtime.failure = failure
      XCTAssertEqual(runtime.runCatchingException() as NSDictionary, ["exception": "PhotosTest"] as NSDictionary)
    }
  }
}
