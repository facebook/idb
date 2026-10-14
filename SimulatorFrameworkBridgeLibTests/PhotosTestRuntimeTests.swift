/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@testable import SimulatorFrameworkBridgeRuntime
import Testing

@Suite
struct PhotosTestRuntimeTests {

  // MARK: - run

  @Test
  func runPropagatesClosureStatus() {
    let runtime = FBPhotosTestRuntime()

    let status = runtime.run { _ in 37 }

    #expect(status == 37)
  }

  @Test
  func runBuildsClientWithConfiguredAssets() {
    let runtime = FBPhotosTestRuntime()
    runtime.assetCount = 3

    let status = runtime.run { client in
      client.deleteAssets() ? 0 : 1
    }

    #expect(status == 0)
    #expect(
      runtime.operations as NSArray == [
        "value:_lazyPhotoLibrary", "unwrap", "transactionBegin", "context",
        "id:asset0", "lookup:asset0", "delete:asset0",
        "id:asset1", "lookup:asset1", "delete:asset1",
        "id:asset2", "lookup:asset2", "delete:asset2",
        "save", "transactionEnd",
      ] as NSArray)
    #expect(runtime.allMutationsInsideTransaction)
  }

  @Test
  func runReturnsAfterWorkerTransactionCompletes() {
    let runtime = FBPhotosTestRuntime()
    runtime.runTransactionsOnWorkerQueue = true

    let status = runtime.run { client in
      client.deleteAssets() ? 0 : 1
    }

    #expect(status == 0)
    #expect(runtime.transactionRanOnWorkerThread)
    #expect(runtime.operations.lastObject as? String == "transactionEnd")
    #expect(runtime.allMutationsInsideTransaction)
    #expect(runtime.escapedTransactionException == nil)
  }

  // MARK: - runCatchingException

  @Test
  func runCatchingExceptionPackagesClosureStatus() {
    let runtime = FBPhotosTestRuntime()

    let result = runtime.runCatchingException { _ in 23 }

    #expect(result["status"] as? Int == 23)
    #expect(result["exception"] == nil)
  }

  @Test
  func runCatchingExceptionCapturesObjectiveCException() {
    let runtime = FBPhotosTestRuntime()

    let result = runtime.runCatchingException { client in
      client.setValue("value", forKey: "missingKey")
      return 0
    }

    #expect(result["exception"] as? String == NSExceptionName.undefinedKeyException.rawValue)
    #expect(result["status"] == nil)
  }
}
