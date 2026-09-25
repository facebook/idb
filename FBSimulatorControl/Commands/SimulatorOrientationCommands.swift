/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Physical device orientation, independently of an application's interface rotation.
public enum SimulatorDeviceOrientation: String, CaseIterable, Sendable, Decodable {
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
        throw SimulatorOrientationError.unwritable(self)
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

public enum SimulatorOrientationError: Error, LocalizedError, Equatable {
  /// Only the four physical directions can be written; flat and unknown states are read-only.
  case unwritable(SimulatorDeviceOrientation)

  public var errorDescription: String? {
    switch self {
    case let .unwritable(orientation): "Device orientation \(orientation.rawValue) cannot be set; choose portrait, portraitUpsideDown, landscapeLeft or landscapeRight"
    }
  }
}

/// The landscape numbering a `SimulatorHIDDeviceOrientation` is written in.
public enum SimulatorOrientationConvention: Sendable {
  /// The physical device convention, the one `current()` reads back.
  case device
  /// Interface-style landscape numbering, which `idb`'s HID stream has always carried. It differs from
  /// `device` only on a runtime without device motion, where landscape left and right are swapped.
  case interface
}

/// How one rotation is written, given the simulator's backend.
enum OrientationWrite: Equatable {
  case vendorHID(SimulatorHIDDeviceOrientation)
  case purple(SimulatorHIDDeviceOrientation)

  init(_ orientation: SimulatorHIDDeviceOrientation, convention: SimulatorOrientationConvention, backend: OrientationWriteBackend) {
    switch (backend, convention) {
    case (.vendorHID, _): self = .vendorHID(orientation)
    case (.purple, .device): self = .purple(orientation.physicalPurpleOrientation)
    case (.purple, .interface): self = .purple(orientation)
    }
  }
}

public struct SimulatorOrientationCommands {
  private let simulator: Simulator

  public static func commands(with simulator: Simulator) -> Self {
    Self(simulator: simulator)
  }

  /// Sets physical device orientation using the same landscape convention as `current()`.
  public func set(_ orientation: SimulatorDeviceOrientation) async throws {
    try await set(orientation.hidOrientation, convention: .device)
  }

  /// Rotates through the backend the simulator's motion capabilities select: vendor HID where the
  /// runtime reports device motion, Purple otherwise.
  public func set(_ orientation: SimulatorHIDDeviceOrientation, convention: SimulatorOrientationConvention) async throws {
    let backend = try await MotionCapabilities.resolve(on: simulator).orientationWriteBackend
    switch OrientationWrite(orientation, convention: convention, backend: backend) {
    case let .vendorHID(orientation):
      try await simulator.hid.vendorDefined.send(orientation.vendorEvent())
    case let .purple(orientation):
      try await simulator.purpleHID.sendOrientation(orientation)
    }
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
