/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let StartCommand: UInt32 = 0x00000000

public final class FBDeviceLocationCommands {
  private weak var device: FBDevice?

  public class func commands(with device: FBDevice) -> FBDeviceLocationCommands {
    FBDeviceLocationCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Async

  fileprivate func overrideLocation(withLongitude longitude: Double, latitude: Double) async throws {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    _ = try await device.ensureDeveloperDiskImageIsMounted()
    try await device.withServiceConnection("com.apple.dt.simulatelocation") { connection in
      var start = StartCommand
      let startData = Data(bytes: &start, count: MemoryLayout<UInt32>.size)
      try connection.send(startData)

      try connection.send(withLengthHeader: Data("\(latitude)".utf8))
      try connection.send(withLengthHeader: Data("\(longitude)".utf8))
    }
  }
}

// MARK: - FBDevice+LocationCommands

extension FBDevice: LocationCommands {

  public func overrideLocation(longitude: Double, latitude: Double) async throws {
    try await location.overrideLocation(withLongitude: longitude, latitude: latitude)
  }
}
