/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBiOSTarget`.
///
/// Composes the new async command protocols (Phase 1.1/1.2) and exposes the same
/// shared informational properties as `FBiOSTarget`. Conformers can adopt this
/// protocol incrementally alongside the existing `@objc FBiOSTarget` conformance.
public protocol AsynciOSTarget: AnyObject,
  AsyncApplicationCommands,
  AsyncVideoStreamCommands,
  AsyncCrashLogCommands,
  AsyncLogCommands,
  AsyncScreenshotCommands,
  AsyncVideoRecordingCommands,
  AsyncXCTestCommands,
  AsyncXCTraceRecordCommands,
  AsyncInstrumentsCommands,
  AsyncLifecycleCommands
{

  // MARK: FBiOSTargetInfo (sync, no FBFuture involved)

  var uniqueIdentifier: String { get }
  var udid: String { get }
  var name: String { get }
  var deviceType: FBDeviceType { get }
  var architectures: [FBArchitecture] { get }
  var osVersion: FBOSVersion { get }
  var extendedInformation: [String: Any] { get }
  var targetType: FBiOSTargetType { get }
  var state: FBiOSTargetState { get }

  // MARK: Shared FBiOSTarget properties (sync, no FBFuture involved)

  var logger: (any FBControlCoreLogger)? { get }
  var customDeviceSetPath: String? { get }
  var temporaryDirectory: FBTemporaryDirectory { get }
  var auxillaryDirectory: String { get }
  var runtimeRootDirectory: String { get }
  var platformRootDirectory: String { get }
  var screenInfo: FBiOSTargetScreenInfo? { get }
  var workQueue: DispatchQueue { get }
  var asyncQueue: DispatchQueue { get }

  func compare(_ target: any AsynciOSTarget) -> ComparisonResult
  func requiresBundlesToBeSigned() -> Bool
  func replacementMapping() -> [String: String]
  func environmentAdditions() -> [String: String]
}
