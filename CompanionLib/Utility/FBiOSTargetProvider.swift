/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@_implementationOnly import FBDeviceControl
@_implementationOnly import FBSimulatorControl
import Foundation
import XCTestBootstrap

@objc public final class FBiOSTargetProvider: NSObject {

  @objc public static func target(withUDID udid: String, targetSets: [FBiOSTargetSet], warmUp: Bool, logger: FBControlCoreLogger) -> FBFuture<AnyObject> {
    let target: FBiOSTarget
    do {
      if udid.lowercased() == "only" {
        target = try fetchSoleTarget(forTargetSets: targetSets, logger: logger)
      } else {
        target = try fetchTarget(withUDID: udid, targetSets: targetSets, logger: logger)
      }
    } catch {
      return FBFuture(error: error)
    }
    if !warmUp {
      return FBFuture(result: target as AnyObject)
    }
    return FBFuture(result: target as AnyObject)
  }

  // MARK: - Private

  private static func fetchTarget(withUDID udid: String, targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) throws -> FBiOSTarget {
    if udid.lowercased() == "mac" {
      return FBMacDevice(logger: logger)
    }
    for targetSet in targetSets {
      guard let targetInfo = targetSet.target(withUDID: udid) else {
        continue
      }
      guard let target = targetInfo as? FBiOSTarget else {
        throw FBDeviceControlError.describe("\(udid) exists, but the target is not usable \(targetInfo)").build()
      }
      return target
    }

    throw FBIDBError.describe("\(udid) could not be resolved to any target in \(targetSets)").build()
  }

  private static func fetchSoleTarget(forTargetSets targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) throws -> FBiOSTarget {
    var targets: [FBiOSTarget] = []
    for targetSet in targetSets {
      for info in targetSet.allTargetInfos {
        if let target = info as? FBiOSTarget {
          targets.append(target)
        }
      }
    }
    if targets.count > 1 {
      throw FBIDBError.describe("Cannot get a sole target when multiple found \(FBCollectionInformation.oneLineDescription(from: targets))").build()
    }
    guard let target = targets.first else {
      throw FBIDBError.describe("Cannot get a sole target when none were found in target sets \(FBCollectionInformation.oneLineDescription(from: targetSets))").build()
    }
    return target
  }
}
