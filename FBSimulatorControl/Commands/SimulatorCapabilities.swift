/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// What a booted simulator can do, so that a caller offers only what it supports rather than probing and
/// classifying the failures.
public struct SimulatorCapabilities: Equatable, Sendable {
  /// Whether `hinge` can set and read the hinge angle.
  public let hingeAngle: Bool
  /// Whether the runtime reports the device's motion state, which orientation reads and writes use.
  public let deviceMotion: Bool
  /// Whether the simulator has more than one integrated display, so that the active one can change.
  public let multipleDisplays: Bool

  public init(hingeAngle: Bool, deviceMotion: Bool, multipleDisplays: Bool) {
    self.hingeAngle = hingeAngle
    self.deviceMotion = deviceMotion
    self.multipleDisplays = multipleDisplays
  }

  /// Throws a failed display read, unless it says the runtime does not report displays.
  init(motion: MotionCapabilities, displays: Result<SimulatorDisplayConfiguration, any Error>) throws {
    let integrated: Int
    do {
      integrated = try displays.get().displays.filter(\.isIntegrated).count
    } catch SimulatorCoreDeviceError.unsupported {
      integrated = 0
    }
    self.init(hingeAngle: motion.supports(.hingeAngle), deviceMotion: motion.supports(.deviceMotionState), multipleDisplays: integrated > 1)
  }
}

extension Simulator {
  /// Throws `SimulatorFailureKind.notReady` failures while services are still starting; a capability a
  /// runtime lacks is reported as unsupported rather than thrown.
  public func capabilities() async throws -> SimulatorCapabilities {
    let motion = try await MotionCapabilities.resolve(on: self)
    let configuration: Result<SimulatorDisplayConfiguration, any Error>
    do {
      configuration = .success(try await displays.configuration(settledWithin: .zero))
    } catch {
      configuration = .failure(error)
    }
    return try SimulatorCapabilities(motion: motion, displays: configuration)
  }
}
