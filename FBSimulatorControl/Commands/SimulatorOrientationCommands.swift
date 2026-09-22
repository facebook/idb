/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Physical device orientation, independently of an application's interface rotation.
public enum SimulatorDeviceOrientation: String, CaseIterable, Sendable {
  case unknown
  case portrait
  case portraitUpsideDown
  case landscapeLeft
  case landscapeRight
  case faceUp
  case faceDown

  var hidOrientation: SimulatorHIDDeviceOrientation {
    get throws {
      switch self {
      case .portrait: return .portrait
      case .portraitUpsideDown: return .portraitUpsideDown
      case .landscapeLeft: return .landscapeLeft
      case .landscapeRight: return .landscapeRight
      case .unknown, .faceUp, .faceDown:
        throw SimulatorCoreDeviceError.unsupported("Setting device orientation to \(rawValue)")
      }
    }
  }

  static func motionState(_ value: Int) throws -> Self {
    switch value {
    case 0: return .unknown
    case 1: return .portrait
    case 2: return .portraitUpsideDown
    case 3: return .landscapeLeft
    case 4: return .landscapeRight
    case 5: return .faceUp
    case 6: return .faceDown
    default: throw SimulatorCoreDeviceError.unavailable("Unrecognized device orientation: \(value)")
    }
  }
}

public struct SimulatorOrientationCommands {
  private let simulator: Simulator

  public static func commands(with simulator: Simulator) -> Self {
    Self(simulator: simulator)
  }

  /// Sets physical device orientation using the same landscape convention as `current()`.
  public func setOrientation(_ orientation: SimulatorDeviceOrientation) async throws {
    let hidOrientation = try orientation.hidOrientation
    try await simulator.lifecycle.connectToHID().sendOrientation(hidOrientation, legacyPurpleEncoding: false)
  }

  public func current() async throws -> SimulatorDeviceOrientation {
    do {
      try await SimulatorMotionCapability.deviceMotionState.requireSupported(on: simulator)
    } catch SimulatorCoreDeviceError.unsupported {
      return try await SimulatorOrientationProtocol.read(on: simulator)
    }
    // The CoreDevice motion stream may replay an old daemon snapshot. A fresh guest client reads
    // the motion provider's current state, including rotations made outside this process.
    let output = try await simulator.runSimulatorFrameworkBridge(withService: "orientation", action: "get")
    return try Self.decodeMotionState(output)
  }

  static func decodeMotionState(_ output: String) throws -> SimulatorDeviceOrientation {
    struct State: Decodable {
      let orientation: Int
    }
    let state = try JSONDecoder().decode(State.self, from: Data(output.utf8))
    return try SimulatorDeviceOrientation.motionState(state.orientation)
  }
}
