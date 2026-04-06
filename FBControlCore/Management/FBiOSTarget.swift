/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - C function replacements via @_cdecl

/// The canonical string representation of the state enum.
@_cdecl("FBiOSTargetStateStringFromState")
func FBiOSTargetStateStringFromState(_ state: FBiOSTargetState) -> FBiOSTargetStateString {
  switch state {
  case .creating:
    return .creating
  case .shutdown:
    return .shutdown
  case .booting:
    return .booting
  case .booted:
    return .booted
  case .shuttingDown:
    return .shuttingDown
  case .DFU:
    return .DFU
  case .recovery:
    return .recovery
  case .restoreOS:
    return .restoreOS
  case .unknown:
    return .unknown
  @unknown default:
    return .unknown
  }
}

/// The canonical enum representation of the state string.
@_cdecl("FBiOSTargetStateFromStateString")
func FBiOSTargetStateFromStateString(_ stateString: FBiOSTargetStateString) -> FBiOSTargetState {
  let normalized = stateString.rawValue.lowercased().replacingOccurrences(of: "-", with: " ")
  if normalized == FBiOSTargetStateString.creating.rawValue.lowercased() {
    return .creating
  }
  if normalized == FBiOSTargetStateString.shutdown.rawValue.lowercased() {
    return .shutdown
  }
  if normalized == FBiOSTargetStateString.booting.rawValue.lowercased() {
    return .booting
  }
  if normalized == FBiOSTargetStateString.booted.rawValue.lowercased() {
    return .booted
  }
  if normalized == FBiOSTargetStateString.shuttingDown.rawValue.lowercased() {
    return .shuttingDown
  }
  if normalized == FBiOSTargetStateString.DFU.rawValue.lowercased() {
    return .DFU
  }
  if normalized == FBiOSTargetStateString.recovery.rawValue.lowercased() {
    return .recovery
  }
  if normalized == FBiOSTargetStateString.restoreOS.rawValue.lowercased() {
    return .restoreOS
  }
  return .unknown
}

/// The canonical string representations of the FBiOSTargetType enum.
@_cdecl("FBiOSTargetTypeStringFromTargetType")
func FBiOSTargetTypeStringFromTargetType(_ targetType: FBiOSTargetType) -> NSString {
  if targetType == .device {
    return "Device"
  }
  if targetType == .simulator {
    return "Simulator"
  }
  if targetType == .localMac {
    return "Mac"
  }
  return "Unknown"
}

/// A Default Comparison Function that can be called for different implementations of FBiOSTarget.
@_cdecl("FBiOSTargetComparison")
func FBiOSTargetComparison(_ left: FBiOSTarget, _ right: FBiOSTarget) -> ComparisonResult {
  var comparison = NSNumber(value: left.targetType.rawValue).compare(NSNumber(value: right.targetType.rawValue))
  if comparison != .orderedSame {
    return comparison
  }
  comparison = left.osVersion.number.compare(right.osVersion.number)
  if comparison != .orderedSame {
    return comparison
  }
  comparison = NSNumber(value: left.deviceType.family.rawValue).compare(NSNumber(value: right.deviceType.family.rawValue))
  if comparison != .orderedSame {
    return comparison
  }
  comparison = left.deviceType.model.rawValue.compare(right.deviceType.model.rawValue)
  if comparison != .orderedSame {
    return comparison
  }
  comparison = NSNumber(value: left.state.rawValue).compare(NSNumber(value: right.state.rawValue))
  if comparison != .orderedSame {
    return comparison
  }
  return left.udid.compare(right.udid)
}

/// Constructs a string description of the provided target.
@_cdecl("FBiOSTargetDescribe")
func FBiOSTargetDescribe(_ target: FBiOSTargetInfo) -> NSString {
  return "\(target.udid) | \(target.name) | \(FBiOSTargetStateStringFromState(target.state).rawValue) | \(target.deviceType.model.rawValue) | \(target.osVersion) " as NSString
}

/// Constructs an NSPredicate matching the specified UDID.
@_cdecl("FBiOSTargetPredicateForUDID")
func FBiOSTargetPredicateForUDID(_ udid: NSString) -> NSPredicate {
  return FBiOSTargetPredicateForUDIDs([udid as String] as NSArray)
}

/// Constructs an NSPredicate matching the specified UDIDs.
@_cdecl("FBiOSTargetPredicateForUDIDs")
func FBiOSTargetPredicateForUDIDs(_ udids: NSArray) -> NSPredicate {
  let udidsSet = Set(udids as! [String])
  return NSPredicate { (evaluatedObject, _) -> Bool in
    guard let candidate = evaluatedObject as? FBiOSTarget else {
      return false
    }
    return udidsSet.contains(candidate.udid)
  }
}

/// Constructs a future that resolves when the target resolves to a provided state.
@_cdecl("FBiOSTargetResolveState")
func FBiOSTargetResolveState(_ target: FBiOSTarget, _ state: FBiOSTargetState) -> FBFuture<NSNull> {
  return FBFuture<AnyObject>.onQueue(
    target.workQueue,
    resolveWhen: {
      return target.state == state
    })
}

/// Constructs a future that resolves when the target leaves a provided state.
@_cdecl("FBiOSTargetResolveLeavesState")
func FBiOSTargetResolveLeavesState(_ target: FBiOSTarget, _ state: FBiOSTargetState) -> FBFuture<NSNull> {
  return FBFuture<AnyObject>.onQueue(
    target.workQueue,
    resolveWhen: {
      return target.state != state
    })
}
