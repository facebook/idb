/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@_implementationOnly import FBDeviceControl
import FBSimulatorControl
import Foundation
import XCTestBootstrap

/// The ways target resolution can fail, as data rather than assembled strings.
public enum FBiOSTargetProviderError: Error {
  case targetNotUsable(udid: String, targetDescription: String)
  case targetNotFound(udid: String, targetSetsDescription: String)
  case multipleTargets(targetsDescription: String)
  case noTargets(targetSetsDescription: String)
  case multipleBootedTargets(targetsDescription: String)
  case noBootedTargets(targetSetsDescription: String)
}

extension FBiOSTargetProviderError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .targetNotUsable(udid, targetDescription):
      return "\(udid) exists, but the target is not usable \(targetDescription)"
    case let .targetNotFound(udid, targetSetsDescription):
      return "\(udid) could not be resolved to any target in \(targetSetsDescription)"
    case let .multipleTargets(targetsDescription):
      return "Cannot get a sole target when multiple found \(targetsDescription)"
    case let .noTargets(targetSetsDescription):
      return "Cannot get a sole target when none were found in target sets \(targetSetsDescription)"
    case let .multipleBootedTargets(targetsDescription):
      return "Cannot get a sole booted target when multiple are booted \(targetsDescription)"
    case let .noBootedTargets(targetSetsDescription):
      return "Cannot get a sole booted target when none are booted in target sets \(targetSetsDescription)"
    }
  }
}

public final class FBiOSTargetProvider {

  public static func target(withUDID udid: String, targetSets: [FBiOSTargetSet], warmUp: Bool, logger: FBControlCoreLogger) throws -> FBiOSTarget {
    switch udid.lowercased() {
    case "only":
      return try fetchSoleTarget(forTargetSets: targetSets, logger: logger)
    case "booted":
      return try fetchSoleBootedTarget(forTargetSets: targetSets, logger: logger)
    default:
      return try fetchTarget(withUDID: udid, targetSets: targetSets, logger: logger)
    }
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
        throw FBiOSTargetProviderError.targetNotUsable(udid: udid, targetDescription: String(describing: targetInfo))
      }
      return target
    }

    throw FBiOSTargetProviderError.targetNotFound(udid: udid, targetSetsDescription: String(describing: targetSets))
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
      throw FBiOSTargetProviderError.multipleTargets(targetsDescription: FBCollectionInformation.oneLineDescription(from: targets))
    }
    guard let target = targets.first else {
      throw FBiOSTargetProviderError.noTargets(targetSetsDescription: FBCollectionInformation.oneLineDescription(from: targetSets))
    }
    return target
  }

  private static func fetchSoleBootedTarget(forTargetSets targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) throws -> FBiOSTarget {
    var bootedTargets: [FBiOSTarget] = []
    for targetSet in targetSets {
      for info in targetSet.allTargetInfos {
        guard let target = info as? FBiOSTarget, target.state == .booted else {
          continue
        }
        bootedTargets.append(target)
      }
    }
    if bootedTargets.count > 1 {
      throw FBiOSTargetProviderError.multipleBootedTargets(targetsDescription: FBCollectionInformation.oneLineDescription(from: bootedTargets))
    }
    guard let target = bootedTargets.first else {
      throw FBiOSTargetProviderError.noBootedTargets(targetSetsDescription: FBCollectionInformation.oneLineDescription(from: targetSets))
    }
    return target
  }
}
