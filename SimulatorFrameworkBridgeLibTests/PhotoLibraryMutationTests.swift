/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Testing

@Suite
struct PhotoLibraryMutationTests {
  @Test
  func clearRetriesAfterSaveFailureAndAcceptsAnEmptyLibrary() throws {
    let runtime = FBPhotosTestRuntime()
    runtime.saveSucceeds = false
    #expect(runtime.run() == 1)
    let failedOperations = try #require(runtime.operations as? [String])
    #expect(failedOperations.contains("save"))
    #expect(failedOperations.last == "transactionEnd")

    runtime.operations.removeAllObjects()
    runtime.saveSucceeds = true
    #expect(runtime.run() == 0)
    #expect(runtime.operations as? [String] == failedOperations)
    #expect(runtime.allMutationsInsideTransaction)

    runtime.operations.removeAllObjects()
    runtime.assetCount = 0
    #expect(runtime.run() == 0)
    #expect(runtime.operations.count == 0)
  }

  @Test
  func emptyLibraryDoesNotAccessPrivateStorage() {
    let runtime = FBPhotosTestRuntime()
    runtime.assetCount = 0
    #expect(runtime.run() == 0)
    #expect(runtime.operations.count == 0)
  }

  @Test
  func deletesEveryAssetAndSavesInsideOneTransaction() {
    for succeeds in [true, false] {
      let runtime = FBPhotosTestRuntime()
      runtime.saveSucceeds = succeeds
      #expect(runtime.run() == (succeeds ? 0 : 1))
      #expect(
        runtime.operations as NSArray == [
          "value:_lazyPhotoLibrary", "unwrap", "transactionBegin", "context",
          "id:asset0", "lookup:asset0", "delete:asset0", "id:asset1", "lookup:asset1", "delete:asset1",
          "save", "transactionEnd",
        ] as NSArray)
      #expect(runtime.allMutationsInsideTransaction)
    }
  }

  @Test
  func unavailablePrivateLibraryStopsBeforeTransaction() {
    for (failure, expected) in [
      ("lazyException", ["value:_lazyPhotoLibrary"]),
      ("unwrapException", ["value:_lazyPhotoLibrary", "unwrap"]),
      ("libraryMissing", ["value:_lazyPhotoLibrary", "unwrap"]),
    ] {
      let runtime = FBPhotosTestRuntime()
      runtime.failure = failure
      #expect(runtime.run() == 1)
      #expect(runtime.operations as NSArray == expected as NSArray)
    }
  }

  @Test
  func workerTransactionFinishesBeforeReturningItsSaveResult() {
    for succeeds in [true, false] {
      let runtime = FBPhotosTestRuntime()
      runtime.runTransactionsOnWorkerQueue = true
      runtime.saveSucceeds = succeeds

      #expect(runtime.run() == (succeeds ? 0 : 1))

      #expect(runtime.transactionRanOnWorkerThread)
      #expect(runtime.allMutationsInsideTransaction)
      #expect(runtime.escapedTransactionException == nil)
      #expect(
        runtime.operations as NSArray == [
          "value:_lazyPhotoLibrary", "unwrap", "transactionBegin", "context",
          "id:asset0", "lookup:asset0", "delete:asset0", "id:asset1", "lookup:asset1", "delete:asset1",
          "save", "transactionEnd",
        ] as NSArray)
    }
  }

  @Test
  func missingObjectsAndExceptionsStopTheTransactionWithoutSaving() {
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
      #expect(runtime.run() == 1)
      #expect(runtime.operations as NSArray == (prefix + body + ["transactionEnd"]) as NSArray)
      #expect(runtime.allMutationsInsideTransaction)
    }
  }
  @Test
  func privateExceptionsReturnCommandFailure() {
    for failure in ["transactionException", "idException", "saveException"] {
      let runtime = FBPhotosTestRuntime()
      runtime.failure = failure
      #expect(runtime.runCatchingException() as NSDictionary == ["status": 1] as NSDictionary)
    }
  }

  @Test
  func privateExceptionsStayInsideTheWorkerTransaction() {
    for failure in ["contextException", "idException", "lookupException", "deleteException", "saveException"] {
      let runtime = FBPhotosTestRuntime()
      runtime.runTransactionsOnWorkerQueue = true
      runtime.failure = failure

      #expect(runtime.run() == 1, "\(failure)")

      #expect(runtime.transactionRanOnWorkerThread, "\(failure)")
      #expect(runtime.escapedTransactionException == nil, "\(failure)")
      #expect((runtime.operations as? [String])?.last == "transactionEnd", "\(failure)")
      if failure != "saveException" {
        #expect(!runtime.operations.contains("save"), "\(failure)")
      } else {
        #expect(runtime.operations.contains("save"), "\(failure)")
      }
    }
  }
}
