/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

// swiftlint:disable force_unwrapping

private let StartCommand: UInt32 = 0x00000000

@objc(FBDeviceLocationCommands)
public class FBDeviceLocationCommands: NSObject, FBiOSTargetCommand {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBLocationCommands (legacy FBFuture entry point)

  public func overrideLocation(withLongitude longitude: Double, latitude: Double) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await overrideLocationAsync(withLongitude: longitude, latitude: latitude)
      return NSNull()
    }
  }

  // MARK: - Async

  fileprivate func overrideLocationAsync(withLongitude longitude: Double, latitude: Double) async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    _ = try await bridgeFBFuture(device.ensureDeveloperDiskImageIsMounted())
    try await withFBFutureContext(device.startService("com.apple.dt.simulatelocation")) { connection in
      var start = StartCommand
      let startData = Data(bytes: &start, count: MemoryLayout<UInt32>.size)
      try connection.send(startData)

      let latitudeString = "\(latitude)"
      let latitudeData = latitudeString.data(using: .utf8)!
      try connection.send(withLengthHeader: latitudeData)

      let longitudeString = "\(longitude)"
      let longitudeData = longitudeString.data(using: .utf8)!
      try connection.send(withLengthHeader: longitudeData)
    }
  }
}

// MARK: - FBDevice+AsyncLocationCommands

extension FBDevice: AsyncLocationCommands {

  public func overrideLocation(longitude: Double, latitude: Double) async throws {
    try await locationCommands().overrideLocationAsync(withLongitude: longitude, latitude: latitude)
  }
}

// MARK: - FBDevice+FBLocationCommands

extension FBDevice: FBLocationCommands {

  @objc(overrideLocationWithLongitude:latitude:)
  public func overrideLocation(withLongitude longitude: Double, latitude: Double) -> FBFuture<NSNull> {
    do {
      return try locationCommands().overrideLocation(withLongitude: longitude, latitude: latitude)
    } catch {
      return FBFuture(error: error)
    }
  }
}
