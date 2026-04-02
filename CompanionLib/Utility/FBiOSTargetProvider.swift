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

  @objc public static func target(withUDID udid: String, targetSets: [FBiOSTargetSet], warmUp: Bool, logger: FBControlCoreLogger?) -> FBFuture<AnyObject> {
    var error: NSError?
    if udid.lowercased() == "only" {
      guard let target = fetchSoleTarget(forTargetSets: targetSets, logger: logger, error: &error) else {
        return FBFuture(error: error!)
      }
      return FBFuture(result: target as AnyObject)
    }
    guard let target = fetchTarget(withUDID: udid, targetSets: targetSets, logger: logger, error: &error) else {
      return FBFuture(error: error!)
    }
    if !warmUp {
      return FBFuture(result: target as AnyObject)
    }
    if target.state != .booted {
      return FBFuture(result: target as AnyObject)
    }
    guard let lifecycle = target as? FBSimulatorLifecycleCommandsProtocol else {
      return FBFuture(result: target as AnyObject)
    }

    if FBXcodeConfiguration.isXcode12_5OrGreater {
      return FBFuture(result: target as AnyObject)
    }

    return lifecycle.connectToBridge().mapReplace(target as AnyObject)
  }

  // MARK: - Private

  private static func fetchTarget(withUDID udid: String, targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger?, error: NSErrorPointer) -> FBiOSTarget? {
    if udid.lowercased() == "mac" {
      return FBMacDevice(logger: logger!)
    }
    for targetSet in targetSets {
      guard let targetInfo = targetSet.target(withUDID: udid) else {
        continue
      }
      guard let target = targetInfo as? FBiOSTarget else {
        error?.pointee = FBControlCoreError.describe("\(udid) exists, but the target is not usable \(targetInfo)").build() as NSError
        return nil
      }
      return target
    }

    error?.pointee = FBIDBError.describe("\(udid) could not be resolved to any target in \(targetSets)").build() as NSError
    return nil
  }

  private static func fetchSoleTarget(forTargetSets targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger?, error: NSErrorPointer) -> FBiOSTarget? {
    var targets: [FBiOSTarget] = []
    for targetSet in targetSets {
      if let infos = targetSet.allTargetInfos as? [FBiOSTarget] {
        targets.append(contentsOf: infos)
      }
    }
    if targets.count > 1 {
      error?.pointee = FBIDBError.describe("Cannot get a sole target when multiple found \(FBCollectionInformation.oneLineDescription(from: targets))").build() as NSError
      return nil
    }
    if targets.isEmpty {
      error?.pointee = FBIDBError.describe("Cannot get a sole target when none were found in target sets \(FBCollectionInformation.oneLineDescription(from: targetSets))").build() as NSError
      return nil
    }
    return targets.first
  }
}
