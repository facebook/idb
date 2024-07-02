/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift
import XCTestBootstrap

struct XCTestListBundlesMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_XctestListBundlesRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_XctestListBundlesResponse {
    let descriptors: [FBXCTestDescriptor] = try await BridgeFuture.value(
      commandExecutor.list_test_bundles()
    )
    return .with {
      $0.bundles = descriptors.map(toBundle(descriptor:))
    }
  }
  private func toBundle(descriptor: FBXCTestDescriptor) -> Idb_XctestListBundlesResponse.Bundles {
    return .with {
      $0.name = descriptor.name
      $0.bundleID = descriptor.testBundleID
      $0.architectures = Array(descriptor.architectures)
    }
  }
}
