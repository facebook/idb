/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public struct DeviceVideoStreamCommands {
  private let device: FBDevice

  public static func commands(with device: FBDevice) -> DeviceVideoStreamCommands {
    DeviceVideoStreamCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Async

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    let session = try await DeviceVideo.captureSession(for: device)
    let stream = try DeviceVideoStream.stream(withSession: session, configuration: configuration, logger: device.logger)
    try await stream.startStreaming(consumer)
    return stream
  }
}

// MARK: - FBDevice+VideoStreamCommands

extension FBDevice: VideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration, to consumer: any FBDataConsumer) async throws -> any FBVideoStream {
    try await videoStream.createStream(configuration: configuration, to: consumer)
  }
}
