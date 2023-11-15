/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import Foundation
import GRPC
import IDBGRPCSwift

struct ListAppsMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_ListAppsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ListAppsResponse {
    let persistedBundleIDs = commandExecutor.storageManager.application.persistedBundleIDs
    let fetchAppProcessState = !request.suppressProcessState
    let apps: [FBInstalledApplication: Any] = try await BridgeFuture.value(commandExecutor.list_apps(fetchAppProcessState))

    return .with {
      $0.apps = apps.map { app, processState in
        .with {
          $0.bundleID = app.bundle.identifier
          $0.name = app.bundle.name
          $0.installType = app.installTypeString
          $0.architectures = app.bundle.binary?.architectures.map(\.rawValue) ?? []
          if let processID = processState as? NSNumber {
            $0.processState = .running
            $0.processIdentifier = processID.uint64Value
          } else {
            $0.processState = .unknown
          }
          $0.debuggable = app.installType == .userDevelopment && persistedBundleIDs.contains(app.bundle.identifier)
        }
      }
    }
  }
}
