/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
internal import FBDeviceControl
import FBSimulatorControl
import Foundation
import XCTestBootstrap

enum TargetProviderError: Error {
  case targetNotUsable(udid: String, targetDescription: String)
  case targetNotFound(udid: String, targetSetsDescription: String)
  case multipleTargets(targetsDescription: String)
  case noTargets(targetSetsDescription: String)
  case multipleBootedTargets(targetsDescription: String)
  case noBootedTargets(targetSetsDescription: String)
}

extension TargetProviderError: LocalizedError {
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

public final class TargetProvider {

  public static func target(withUDID udid: String, targetSets: [TargetSet], warmUp: Bool, logger: ControlCoreLogger) throws -> any Target {
    switch udid.lowercased() {
    case "only":
      return try fetchSoleTarget(forTargetSets: targetSets, logger: logger)
    case "booted":
      return try fetchSoleBootedTarget(forTargetSets: targetSets, logger: logger)
    default:
      return try fetchTarget(withUDID: udid, targetSets: targetSets, logger: logger)
    }
  }

  private static func fetchTarget(withUDID udid: String, targetSets: [TargetSet], logger: ControlCoreLogger) throws -> any Target {
    if udid.lowercased() == "mac" {
      return MacDevice(logger: logger)
    }
    for targetSet in targetSets {
      guard let targetInfo = targetSet.target(withUDID: udid) else {
        continue
      }
      guard let target = targetInfo as? any Target else {
        throw TargetProviderError.targetNotUsable(udid: udid, targetDescription: String(describing: targetInfo))
      }
      return target
    }

    throw TargetProviderError.targetNotFound(udid: udid, targetSetsDescription: String(describing: targetSets))
  }

  private static func fetchSoleTarget(forTargetSets targetSets: [TargetSet], logger: ControlCoreLogger) throws -> any Target {
    var targets: [any Target] = []
    for targetSet in targetSets {
      for info in targetSet.allTargetInfos {
        if let target = info as? any Target {
          targets.append(target)
        }
      }
    }
    if targets.count > 1 {
      throw TargetProviderError.multipleTargets(targetsDescription: CollectionInformation.oneLineDescription(from: targets))
    }
    guard let target = targets.first else {
      throw TargetProviderError.noTargets(targetSetsDescription: CollectionInformation.oneLineDescription(from: targetSets))
    }
    return target
  }

  private static func fetchSoleBootedTarget(forTargetSets targetSets: [TargetSet], logger: ControlCoreLogger) throws -> any Target {
    var bootedTargets: [any Target] = []
    for targetSet in targetSets {
      for info in targetSet.allTargetInfos {
        guard let target = info as? any Target, target.state == .booted else {
          continue
        }
        bootedTargets.append(target)
      }
    }
    if bootedTargets.count > 1 {
      throw TargetProviderError.multipleBootedTargets(targetsDescription: CollectionInformation.oneLineDescription(from: bootedTargets))
    }
    guard let target = bootedTargets.first else {
      throw TargetProviderError.noBootedTargets(targetSetsDescription: CollectionInformation.oneLineDescription(from: targetSets))
    }
    return target
  }
}
