/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - FBiOSTargetCommand Protocol

/// A protocol that defines a command class that can be instantiated for a target.
/// Concrete command classes (e.g. `FBSimulatorApplicationCommands`) adopt this directly.
public protocol FBiOSTargetCommand: AnyObject {
  /// Instantiates the Commands instance.
  static func commands(with target: any FBiOSTarget) -> Self
}

// MARK: - FBiOSTargetInfo Protocol

/// A protocol that defines an informational target.
public protocol FBiOSTargetInfo: AnyObject {

  /// A Unique Identifier that describes this iOS Target.
  var uniqueIdentifier: String { get }

  /// The "Unique Device Identifier" of the iOS Target.
  /// This may be distinct from the uniqueIdentifier.
  var udid: String { get }

  /// The Name of the iOS Target. This is the name given by the user, such as "Ada's iPhone"
  var name: String { get }

  /// The Device Type of the Target.
  var deviceType: FBDeviceType { get }

  /// Available architecture of the iOS Target
  var architectures: [FBArchitecture] { get }

  /// The OS Version of the Target.
  var osVersion: FBOSVersion { get }

  /// A dictionary containing per-target-type information that is unique to them.
  /// For example iOS Devices have additional metadata that is not present on Simulators.
  /// This dictionary must be JSON-Serializable.
  var extendedInformation: [String: Any] { get }

  /// The Type of the iOS Target
  var targetType: FBiOSTargetType { get }

  /// The State of the iOS Target. Currently only applies to Simulators.
  var state: FBiOSTargetState { get }
}

// MARK: - FBiOSTarget Protocol

/// A protocol that defines an interactible and informational target.
public protocol FBiOSTarget: FBiOSTargetInfo, FBiOSTargetCommand {

  /// The Target's Logger.
  var logger: any FBControlCoreLogger { get }

  /// The path to the custom (non-default) device set if applicable.
  var customDeviceSetPath: String? { get }

  /// The directory that the target uses to store scratch files on the host.
  var temporaryDirectory: FBTemporaryDirectory { get }

  /// The directory that the target uses to store per-target files on the host.
  /// This should only be used for storing files that need to be preserved over the lifespan of the target.
  /// For example scratch or temporary files should *not* be stored here and temporaryDirectory should be used instead.
  var auxillaryDirectory: String { get }

  /// The root of the "Runtime" where applicable
  var runtimeRootDirectory: String { get async }

  /// The root of the "Platform" where applicable
  var platformRootDirectory: String { get async }

  /// The Screen Info for the Target.
  var screenInfo: FBiOSTargetScreenInfo? { get }

  /// The Queue to serialize work on.
  /// This is a serial queue that should act as a lock for other tasks that will mutate the state of the target.
  /// Mutually Exclusive operations should use this queue.
  var workQueue: DispatchQueue { get }

  /// A queue for independent operations to execute on.
  /// Examples of these operations are transforming an immutable data structure.
  var asyncQueue: DispatchQueue { get }

  /// A Comparison Method for `sortedArrayUsingSelector:`
  func compare(_ target: any FBiOSTarget) -> ComparisonResult

  /// If the target's bundle needs to be codesigned or not.
  func requiresBundlesToBeSigned() -> Bool

  /// Env var replacements
  func replacementMapping() -> [String: String]

  /// Env var additions
  func environmentAdditions() -> [String: String]
}

/// String representations of `FBiOSTargetState`.
///
/// The state enum's numeric values are not stable across releases; these strings are, and are what
/// gets serialised.
public enum FBiOSTargetStateString: String, Sendable, CaseIterable {
  case creating = "Creating"
  case shutdown = "Shutdown"
  case booting = "Booting"
  case booted = "Booted"
  case shuttingDown = "Shutting Down"
  case DFU = "DFU"
  case recovery = "Recovery"
  case restoreOS = "RestoreOS"
  case unknown = "Unknown"
}

// MARK: - State conversions

/// The canonical string representation of the state enum.
public func FBiOSTargetStateStringFromState(_ state: FBiOSTargetState) -> FBiOSTargetStateString {
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
public func FBiOSTargetStateFromStateString(_ stateString: FBiOSTargetStateString) -> FBiOSTargetState {
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
public func FBiOSTargetTypeStringFromTargetType(_ targetType: FBiOSTargetType) -> String {
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

/// The canonical string representation of a product family (the device "type":
/// iphone, ipad, watch, tv, mac), distinct from the simulator/device/mac
/// distinction carried by FBiOSTargetType.
public func FBControlCoreProductFamilyString(_ family: FBControlCoreProductFamily) -> String {
  switch family {
  case .familyiPhone:
    return "iphone"
  case .familyiPad:
    return "ipad"
  case .familyAppleWatch:
    return "watch"
  case .familyAppleTV:
    return "tv"
  case .familyMac:
    return "mac"
  case .familyUnknown:
    return "unknown"
  @unknown default:
    return "unknown"
  }
}

/// A Default Comparison Function that can be called for different implementations of FBiOSTarget.
public func FBiOSTargetComparison(_ left: FBiOSTarget, _ right: FBiOSTarget) -> ComparisonResult {
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
public func FBiOSTargetDescribe(_ target: FBiOSTargetInfo) -> String {
  return "\(target.udid) | \(target.name) | \(FBiOSTargetStateStringFromState(target.state).rawValue) | \(target.deviceType.model.rawValue) | \(target.osVersion) "
}

/// Constructs an NSPredicate matching the specified UDID.
public func FBiOSTargetPredicateForUDID(_ udid: String) -> NSPredicate {
  return FBiOSTargetPredicateForUDIDs([udid])
}

/// Constructs an NSPredicate matching the specified UDIDs.
public func FBiOSTargetPredicateForUDIDs(_ udids: [String]) -> NSPredicate {
  let udidsSet = Set(udids)
  return NSPredicate { (evaluatedObject, _) -> Bool in
    guard let candidate = evaluatedObject as? FBiOSTarget else {
      return false
    }
    return udidsSet.contains(candidate.udid)
  }
}

/// Waits until the target resolves to a provided state.
///
/// - Parameter deadline: How long to wait for. Waits indefinitely when `nil`.
public func FBiOSTargetResolveState(
  _ target: FBiOSTarget,
  _ state: FBiOSTargetState,
  deadline: PollDeadline? = nil
) async throws {
  let box = TargetBox(target)
  try await awaitTargetState(box, deadline: deadline) { box.target.state == state }
}

/// Waits until the target leaves a provided state.
///
/// - Parameter deadline: How long to wait for. Waits indefinitely when `nil`.
public func FBiOSTargetResolveLeavesState(
  _ target: FBiOSTarget,
  _ state: FBiOSTargetState,
  deadline: PollDeadline? = nil
) async throws {
  let box = TargetBox(target)
  try await awaitTargetState(box, deadline: deadline) { box.target.state != state }
}

/// Carries a target into the `@Sendable` polling closure. The target is read only for its `state`,
/// and only on its own work queue, which is the serialisation point the protocol documents.
private final class TargetBox: @unchecked Sendable {
  let target: FBiOSTarget
  init(_ target: FBiOSTarget) {
    self.target = target
  }
}

private func awaitTargetState(
  _ box: TargetBox,
  deadline: PollDeadline?,
  condition: @escaping @Sendable () -> Bool
) async throws {
  let future = FBFuture<AnyObject>.onQueue(box.target.workQueue, resolveWhen: condition)
  guard let deadline else {
    try await bridgeFBFutureVoid(future)
    return
  }
  try await bridgeFBFutureVoid(future.timeout(deadline.timeout, waitingFor: deadline.waitingFor))
}
