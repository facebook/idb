/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A physical pose of the simulated device that moves its displays.
public enum SimulatorPose: Equatable, Sendable, CustomStringConvertible {
  case hinge(SimulatorHingeAngle)
  case orientation(SimulatorDeviceOrientation)

  public var description: String {
    switch self {
    case let .hinge(angle): "hinge at \(angle.degrees) degrees"
    case let .orientation(orientation): "device orientation \(orientation.rawValue)"
    }
  }
}

/// Why a hinge or orientation change was not confirmed within its budget.
public enum SimulatorPoseConfirmationError: Error, LocalizedError, Equatable {
  case notReached(target: SimulatorPose, last: SimulatorPose)

  public var errorDescription: String? {
    switch self {
    case let .notReached(target, last): "Simulator did not reach \(target); last read \(last)"
    }
  }
}

/// A pose that can be written and read back, so that a change to it can be confirmed.
protocol PoseCommands {
  associatedtype Value

  var displays: any DisplayCommands { get }

  func set(_ value: Value) async throws

  func current() async throws -> Value

  func reached(_ value: Value, target: Value) -> Bool

  func pose(_ value: Value) -> SimulatorPose
}

extension PoseCommands {

  /// Sets `target`, then reads the pose until it is reached and waits for the displays to settle, all within
  /// `timeout`. The configuration is `.transitioning` when the displays outlast the budget.
  func set(
    _ target: Value, confirmingWithin timeout: Duration, interval: Duration
  ) async throws -> SimulatorDisplayConfiguration {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    try await set(target)
    while true {
      let value = try await current()
      if reached(value, target: target) { break }
      guard clock.now < deadline else { throw SimulatorPoseConfirmationError.notReached(target: pose(target), last: pose(value)) }
      try await Task.sleep(for: interval)
    }
    return try await displays.settledConfiguration(within: max(deadline - clock.now, .zero))
  }
}
