/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

public struct SimulatorOrientationCommands {
  private let simulator: Simulator

  public init(simulator: Simulator) {
    self.simulator = simulator
  }

  /// Sets physical device orientation using the same landscape convention as `current()`.
  public func set(_ orientation: SimulatorDeviceOrientation) async throws {
    try await simulator.writeOrientation(orientation)
  }

  /// Sets physical device orientation, then waits within `timeout` for `current()` to read it back and for the
  /// displays to settle, returning a `.transitioning` configuration when they outlast the budget. The foreground
  /// application may rotate its interface later, or not at all; follow `SimulatorDisplayCommands.configurations()`
  /// to see it.
  public func set(
    _ orientation: SimulatorDeviceOrientation, confirmingWithin timeout: Duration
  ) async throws
    -> SimulatorDisplayConfiguration
  {
    try await set(orientation, confirmingWithin: timeout, interval: .milliseconds(100))
  }

  /// Rotates through the backend the simulator's motion capabilities select: vendor HID where the
  /// runtime reports device motion, Purple otherwise.
  public func set(_ orientation: SimulatorHIDDeviceOrientation, convention: SimulatorOrientationConvention) async throws {
    try await simulator.writeOrientation(orientation, convention: convention)
  }

  public func current() async throws -> SimulatorDeviceOrientation {
    switch try await MotionCapabilities.resolve(on: simulator).orientationReadBackend {
    case .legacyService:
      return try await SimulatorOrientationProtocol.read(on: simulator)
    case .guestMotionState:
      // A fresh guest client reads the motion provider's current state, including rotations made
      // outside this process.
      let output = try await simulator.runSimulatorFrameworkBridge(withService: "orientation", action: "get")
      return try Self.decodeMotionState(output)
    }
  }

  static func decodeMotionState(_ output: String) throws -> SimulatorDeviceOrientation {
    struct State: Decodable {
      let orientation: Int
    }
    let state = try JSONDecoder().decode(State.self, from: Data(output.utf8))
    return try SimulatorDeviceOrientation.motionState(state.orientation)
  }
}

extension SimulatorOrientationCommands: PoseCommands {
  package var displays: any DisplayCommands { simulator.displays }

  package func reached(_ value: SimulatorDeviceOrientation, target: SimulatorDeviceOrientation) -> Bool { value == target }

  package func pose(_ value: SimulatorDeviceOrientation) -> SimulatorPose { .orientation(value) }
}
