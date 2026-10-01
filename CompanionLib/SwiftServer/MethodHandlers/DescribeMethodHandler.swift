/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
import FBControlCore
import FBSimulatorControl
import Foundation
import GRPCCore
import IDBGRPCSwift

struct DescribeMethodHandler {

  let reporter: EventReporter
  let logger: IDBLogger
  let target: any Target
  let commandExecutor: IDBCommandExecutor
  let streamCapabilities: StreamCapabilities

  func handle(request: Idb_TargetDescriptionRequest, context: ServerContext) async throws -> Idb_TargetDescriptionResponse {
    let displays = await readDisplays()
    var response = Idb_TargetDescriptionResponse.with {
      $0.targetDescription = .with {
        $0.udid = target.udid
        $0.name = target.name
        $0.state = target.state.stateString.rawValue
        $0.targetType = target.targetType.stringRepresentation.lowercased()
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
        $0.displays = displays.map(Self.display)
      }
      $0.companion = Idb_CompanionInfo.with {
        $0.udid = target.udid
        $0.setStreamCapabilities(streamCapabilities)
        if let metadata = try? JSONSerialization.data(withJSONObject: reporter.metadata) {
          $0.metadata = metadata
        }
      }
    }

    guard request.fetchDiagnostics else {
      return response
    }

    let diagnosticInformation = try await commandExecutor.diagnostic_information()
    let diagnosticInfoData = try JSONSerialization.data(withJSONObject: diagnosticInformation)
    response.targetDescription.diagnostics = diagnosticInfoData

    return response
  }

  static func display(_ display: SimulatorDisplay) -> Idb_Display {
    .with {
      $0.uniqueID = display.uniqueID
      $0.name = display.name
      $0.active = display.isActive
      $0.integrated = display.isIntegrated
      $0.width = UInt64(exactly: display.size.width.rounded()) ?? 0
      $0.height = UInt64(exactly: display.size.height.rounded()) ?? 0
      $0.density = display.scale
    }
  }

  // A description is still useful without displays, so a failed read leaves them out.
  private func readDisplays() async -> [SimulatorDisplay] {
    guard let simulator = target as? Simulator, target.state == .booted else {
      return []
    }
    do {
      return try await simulator.displays.list()
    } catch {
      logger.info().log("Describing \(target.udid) without displays: \(error)")
      return []
    }
  }
}
