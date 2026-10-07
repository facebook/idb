/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import FBSimulatorControl
import FBSimulatorVideo
import FBVideoCore
import Foundation
import XCTestBootstrap

/// The target the companion serves, with every capability its handlers reach. Resolved once, when the
/// target is chosen, so a handler never asks whether the target has a capability.
public typealias CompanionTarget = any VideoTarget

extension TargetProvider {

  /// Each target type the companion serves is named rather than found with `as? any VideoTarget`. That
  /// cast only finds a conformance something else has already pulled out of its archive, and one declared
  /// in a library of its own may have nothing else referencing it.
  static func companionTarget(_ target: any TargetInfo) -> CompanionTarget? {
    switch target {
    case let simulator as Simulator:
      return simulator
    case let device as Device:
      return device
    case let mac as MacDevice:
      return mac
    default:
      return nil
    }
  }
}

/// The local Mac has no screen to record; its video commands fail the way its other unsupported commands do.
extension MacDevice: @retroactive VideoTarget {

  public var videoRecording: MacUnsupportedVideoCommands { MacUnsupportedVideoCommands() }

  public var videoStream: MacUnsupportedVideoCommands { MacUnsupportedVideoCommands() }
}

public struct MacUnsupportedVideoCommands: VideoRecordingCommands, VideoStreamCommands {

  public func start(toFile filePath: String) async throws -> any VideoRecording {
    throw MacDeviceError.commandUnsupported(command: "start")
  }

  public func create(configuration: VideoStreamConfiguration, to consumer: any DataConsumer) async throws -> any VideoStreamOperation {
    throw MacDeviceError.commandUnsupported(command: "create")
  }
}
