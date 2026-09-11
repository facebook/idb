/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - FBiOSTargetCommand Protocol

/// A protocol that defines a command class that can be instantiated for a target.
/// Concrete command classes (e.g. `SimulatorApplicationCommands`) adopt this directly.
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
  var deviceType: DeviceType { get }

  /// Available architecture of the iOS Target
  var architectures: [FBArchitecture] { get }

  /// The OS Version of the Target.
  var osVersion: OSVersion { get }

  /// A dictionary containing per-target-type information that is unique to them.
  /// For example iOS Devices have additional metadata that is not present on Simulators.
  /// This dictionary must be JSON-Serializable.
  var extendedInformation: [String: Any] { get }

  /// The Type of the iOS Target
  var targetType: FBiOSTargetType { get }

  /// The State of the iOS Target. Currently only applies to Simulators.
  var state: FBiOSTargetState { get }

  /// A Comparison Method for `sortedArrayUsingSelector:`
  func compare(_ target: any FBiOSTargetInfo) -> ComparisonResult
}

extension FBiOSTargetInfo {

  public func compare(_ target: any FBiOSTargetInfo) -> ComparisonResult {
    var comparison = NSNumber(value: targetType.rawValue).compare(NSNumber(value: target.targetType.rawValue))
    if comparison != .orderedSame {
      return comparison
    }
    comparison = osVersion.number.compare(target.osVersion.number)
    if comparison != .orderedSame {
      return comparison
    }
    comparison = NSNumber(value: deviceType.family.rawValue).compare(NSNumber(value: target.deviceType.family.rawValue))
    if comparison != .orderedSame {
      return comparison
    }
    comparison = deviceType.model.rawValue.compare(target.deviceType.model.rawValue)
    if comparison != .orderedSame {
      return comparison
    }
    comparison = NSNumber(value: state.rawValue).compare(NSNumber(value: target.state.rawValue))
    if comparison != .orderedSame {
      return comparison
    }
    return udid.compare(target.udid)
  }

  /// A one-line description of the target.
  public var targetDescription: String {
    "\(udid) | \(name) | \(state.stateString.rawValue) | \(deviceType.model.rawValue) | \(osVersion) "
  }
}

// MARK: - FBiOSTarget Protocol

/// A protocol that defines an interactible and informational target.
public protocol FBiOSTarget: FBiOSTargetInfo, FBiOSTargetCommand {

  // MARK: - Command nouns

  // The target's capabilities, one accessor per capability. A caller reaches an operation through
  // the noun that owns it — `target.power.shutdown()` — rather than through a verb on the target.
  //
  // Each noun is an associated type rather than the capability existential so that a concrete target
  // keeps the concrete command type: `simulator.lifecycle` is a `SimulatorLifecycleCommands`, with
  // the simulator-only operations it adds. A caller holding `any FBiOSTarget` sees the capability
  // upper bound, `any LifecycleCommands`.

  associatedtype Application: ApplicationCommands
  var application: Application { get }

  associatedtype CrashLog: CrashLogCommands
  var crashLog: CrashLog { get }

  associatedtype Debugger: DebuggerCommands
  var debugger: Debugger { get }

  associatedtype Erase: EraseCommands
  var erase: Erase { get }

  associatedtype File: FileCommands
  var file: File { get }

  associatedtype Instruments: InstrumentsCommands
  var instruments: Instruments { get }

  associatedtype Lifecycle: LifecycleCommands
  var lifecycle: Lifecycle { get }

  associatedtype Location: LocationCommands
  var location: Location { get }

  associatedtype Log: LogCommands
  var log: Log { get }

  associatedtype Power: PowerCommands
  var power: Power { get }

  associatedtype Screenshot: ScreenshotCommands
  var screenshot: Screenshot { get }

  associatedtype VideoRecording: VideoRecordingCommands
  var videoRecording: VideoRecording { get }

  associatedtype VideoStream: VideoStreamCommands
  var videoStream: VideoStream { get }

  associatedtype XCTraceRecord: XCTraceRecordCommands
  var xctraceRecord: XCTraceRecord { get }

  // MARK: - Target properties

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

extension FBiOSTargetState {

  /// The canonical string representation of the state enum.
  public var stateString: FBiOSTargetStateString {
    switch self {
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
}

extension FBiOSTargetType {

  /// The canonical string representation of the target type.
  public var stringRepresentation: String {
    if self == .device {
      return "Device"
    }
    if self == .simulator {
      return "Simulator"
    }
    if self == .localMac {
      return "Mac"
    }
    return "Unknown"
  }
}

extension FBControlCoreProductFamily {

  /// The canonical string representation of the product family (the device "type": iphone, ipad,
  /// watch, tv, mac), distinct from the simulator/device/mac distinction of FBiOSTargetType.
  public var stringRepresentation: String {
    switch self {
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
}

/// Constructs an NSPredicate matching the specified UDID.
public func FBiOSTargetPredicateForUDID(_ udid: String) -> NSPredicate {
  return FBiOSTargetPredicateForUDIDs([udid])
}

/// Constructs an NSPredicate matching the specified UDIDs.
public func FBiOSTargetPredicateForUDIDs(_ udids: [String]) -> NSPredicate {
  let udidsSet = Set(udids)
  return NSPredicate { (evaluatedObject, _) -> Bool in
    guard let candidate = evaluatedObject as? FBiOSTargetInfo else {
      return false
    }
    return udidsSet.contains(candidate.udid)
  }
}

/// Waits until the target resolves to a provided state.
///
/// - Parameter deadline: How long to wait for. Waits indefinitely when `nil`.
public func FBiOSTargetResolveState(
  _ target: any FBiOSTarget,
  _ state: FBiOSTargetState,
  deadline: PollDeadline? = nil
) async throws {
  let box = TargetBox(target)
  try await pollUntilTrue(on: target.workQueue, deadline: deadline) { box.target.state == state }
}

/// Waits until the target leaves a provided state.
///
/// - Parameter deadline: How long to wait for. Waits indefinitely when `nil`.
public func FBiOSTargetResolveLeavesState(
  _ target: any FBiOSTarget,
  _ state: FBiOSTargetState,
  deadline: PollDeadline? = nil
) async throws {
  let box = TargetBox(target)
  try await pollUntilTrue(on: target.workQueue, deadline: deadline) { box.target.state != state }
}

/// Carries a target into the `@Sendable` polling closure. The target is read only for its `state`,
/// and only on its own work queue, which is the serialisation point the protocol documents.
private final class TargetBox: @unchecked Sendable {
  let target: any FBiOSTarget
  init(_ target: any FBiOSTarget) {
    self.target = target
  }
}
