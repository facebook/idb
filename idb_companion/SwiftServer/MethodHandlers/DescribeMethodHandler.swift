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

struct DescribeMethodHandler {

  let reporter: FBEventReporter
  let logger: FBIDBLogger
  let target: FBiOSTarget
  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_TargetDescriptionRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_TargetDescriptionResponse {
    var response = Idb_TargetDescriptionResponse.with {
      $0.targetDescription = .with {
        $0.udid = target.udid
        $0.name = target.name
        $0.state = FBiOSTargetStateStringFromState(target.state).rawValue
        $0.targetType = FBiOSTargetTypeStringFromTargetType(target.targetType).lowercased()
        $0.osVersion = target.osVersion.name.rawValue
        if let screenInfo = target.screenInfo {
          $0.screenDimensions = .with {
            $0.width = UInt64(screenInfo.widthPixels)
            $0.widthPoints = $0.width / UInt64(screenInfo.scale)
            $0.height = UInt64(screenInfo.heightPixels)
            $0.heightPoints = $0.height / UInt64(screenInfo.scale)
            $0.density = Double(screenInfo.scale)
          }
        }
        if let extData = try? JSONSerialization.data(withJSONObject: target.extendedInformation) {
          $0.extended = extData
        }
      }
      $0.companion = Idb_CompanionInfo.with {
        $0.udid = target.udid
        if let metadata = try? JSONSerialization.data(withJSONObject: reporter.metadata) {
          $0.metadata = metadata
        }
      }
    }

    guard request.fetchDiagnostics else {
      return response
    }

    let diagnosticInformation = try await BridgeFuture.value(commandExecutor.diagnostic_information())
    let diagnosticInfoData = try JSONSerialization.data(withJSONObject: diagnosticInformation)
    response.targetDescription.diagnostics = diagnosticInfoData

    return response
  }

  private func populateCompanionInfo(info: inout Idb_CompanionInfo) throws {
    info.udid = target.udid
    let data = try JSONSerialization.data(withJSONObject: reporter.metadata, options: [])
    info.metadata = data
  }
}
