/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

// swiftlint:disable force_unwrapping

@objc(FBDeviceSocketForwardingCommands)
public class FBDeviceSocketForwardingCommands: NSObject, FBiOSTargetCommand {
  private(set) weak var device: FBDevice?

  // MARK: Initializers

  @objc public class func commands(with target: any FBiOSTarget) -> Self {
    return unsafeDowncast(FBDeviceSocketForwardingCommands(device: target as! FBDevice), to: self)
  }

  init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: FBSocketForwardingCommands (legacy FBFuture entry point)

  public func drainLocalFileInput(
    _ localFileDescriptorInput: Int32,
    localFileOutput localFileDescriptorOutput: Int32,
    remotePort: Int32
  ) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await drainLocalFileInputAsync(
        localFileDescriptorInput,
        localFileOutput: localFileDescriptorOutput,
        remotePort: remotePort)
      return NSNull()
    }
  }

  // MARK: - Async

  fileprivate func drainLocalFileInputAsync(
    _ localFileDescriptorInput: Int32,
    localFileOutput localFileDescriptorOutput: Int32,
    remotePort: Int32
  ) async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    var error: NSError?
    guard let localConsumer = FBFileWriter.asyncWriter(withFileDescriptor: localFileDescriptorOutput, closeOnEndOfFile: false, error: &error) else {
      throw error!
    }
    try await withFBFutureContext(device.connectToDevice(withPurpose: "Socket Connection")) { connectedDevice in
      let localSocket = try Self.openLocalSocket(toRemotePort: Int(remotePort), on: connectedDevice, logger: device.logger)
      defer {
        device.logger?.log("Closing local socket \(localSocket)")
        close(localSocket)
      }
      var writerError: NSError?
      guard let remoteWriter = FBFileWriter.asyncWriter(withFileDescriptor: localSocket, closeOnEndOfFile: false, error: &writerError) else {
        throw writerError!
      }
      let remoteReader = FBFileReader.reader(withFileDescriptor: localSocket, closeOnEndOfFile: false, consumer: localConsumer, logger: nil)
      try await bridgeFBFutureVoid(remoteReader.startReading())

      let inputReader = FBFileReader.reader(withFileDescriptor: localFileDescriptorInput, closeOnEndOfFile: false, consumer: remoteWriter, logger: nil)
      try await bridgeFBFutureVoid(inputReader.startReading())
      _ = try await bridgeFBFuture(inputReader.finishedReading)
    }
  }

  // MARK: Private

  private static func openLocalSocket(toRemotePort remotePort: Int, on device: any FBDeviceCommands, logger: (any FBControlCoreLogger)?) throws -> Int32 {
    guard let getConnectionID = device.calls.GetConnectionID else {
      throw FBDeviceControlError.describe("GetConnectionID not available").build()
    }
    let connectionID = getConnectionID(device.amDeviceRef)
    if connectionID <= 0 {
      throw FBDeviceControlError.describe("Failed to get ConnectionID from Device").build()
    }
    logger?.log("Got connection ID \(connectionID), for device. Connecting to remote port \(remotePort)")
    var localSocket: Int32 = 0
    guard let usbMuxConnect = device.calls.USBMuxConnectByPort else {
      throw FBDeviceControlError.describe("USBMuxConnectByPort not available").build()
    }
    let status = usbMuxConnect(connectionID, Int32(UInt16(remotePort).bigEndian), &localSocket)
    if status != 0 {
      throw FBDeviceControlError.describe("Failed to connect to remote port \(remotePort)").build()
    }
    logger?.log("Got local socket \(localSocket) for remote port \(remotePort)")
    return localSocket
  }
}
