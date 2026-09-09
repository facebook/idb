/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public enum FBDeviceSocketForwardingError: Error {
  case fileDescriptorWriterFailed(fileDescriptor: Int32)
  case socketDuplicationFailed(message: String)
  case socketWriterFailed(socket: Int32)
  case callUnavailable(function: String)
  case connectionIDUnavailable
  case remoteConnectionFailed(remotePort: Int)
}

extension FBDeviceSocketForwardingError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .fileDescriptorWriterFailed(fileDescriptor):
      return "Failed to create a writer for local file descriptor \(fileDescriptor)"
    case let .socketDuplicationFailed(message):
      return "Could not duplicate socket descriptor: \(message)"
    case let .socketWriterFailed(socket):
      return "Failed to create a writer for local socket \(socket)"
    case let .callUnavailable(function):
      return "\(function) not available"
    case .connectionIDUnavailable:
      return "Failed to get ConnectionID from Device"
    case let .remoteConnectionFailed(remotePort):
      return "Failed to connect to remote port \(remotePort)"
    }
  }
}

public final class FBDeviceSocketForwardingCommands {
  private(set) weak var device: FBDevice?

  public class func commands(with device: FBDevice) -> FBDeviceSocketForwardingCommands {
    FBDeviceSocketForwardingCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Socket forwarding

  fileprivate func drainLocalFileInput(
    _ localFileDescriptorInput: Int32,
    localFileOutput localFileDescriptorOutput: Int32,
    remotePort: Int32
  ) async throws {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    var error: NSError?
    guard let localConsumer = FBFileWriter.asyncWriter(withFileDescriptor: localFileDescriptorOutput, closeOnEndOfFile: false, error: &error) else {
      throw error ?? FBDeviceSocketForwardingError.fileDescriptorWriterFailed(fileDescriptor: localFileDescriptorOutput)
    }
    try await device.withConnectedDevice(purpose: "Socket Connection") { connectedDevice in
      let localSocket = try Self.openLocalSocket(toRemotePort: Int(remotePort), on: connectedDevice, logger: device.logger)
      // The writer gets its own duplicate of the socket, owned and closed by its channel. Two
      // dispatch io channels must not share one descriptor: they share a per-descriptor entry
      // inside libdispatch, and one channel's cleanup is deferred behind the other's outstanding
      // operations, wedging teardown.
      let writerDescriptor = dup(localSocket)
      guard writerDescriptor >= 0 else {
        close(localSocket)
        throw FBDeviceSocketForwardingError.socketDuplicationFailed(message: String(cString: strerror(errno)))
      }
      var writerError: NSError?
      guard let remoteWriter = FBFileWriter.asyncWriter(withFileDescriptor: writerDescriptor, closeOnEndOfFile: true, error: &writerError) else {
        close(writerDescriptor)
        close(localSocket)
        throw writerError ?? FBDeviceSocketForwardingError.socketWriterFailed(socket: localSocket)
      }
      let remoteReader = FBFileReader.reader(withFileDescriptor: localSocket, closeOnEndOfFile: false, consumer: localConsumer, logger: nil)
      let inputReader = FBFileReader.reader(withFileDescriptor: localFileDescriptorInput, closeOnEndOfFile: false, consumer: remoteWriter, logger: nil)
      do {
        try await bridgeFBFutureVoid(remoteReader.startReading())
        try await bridgeFBFutureVoid(inputReader.startReading())
        _ = try await bridgeFBFuture(inputReader.finishedReading)
      } catch {
        await Self.stopForwarding(inputReader: inputReader, remoteReader: remoteReader, remoteWriter: remoteWriter, localSocket: localSocket, logger: device.logger)
        throw error
      }
      await Self.stopForwarding(inputReader: inputReader, remoteReader: remoteReader, remoteWriter: remoteWriter, localSocket: localSocket, logger: device.logger)
    }
  }

  /// Matches `FBProcessOutput`'s detach drain timeout: how long to wait for a
  /// reader to finish naturally before stopping it.
  private static let teardownDrainTimeout: TimeInterval = 4

  // The reader dispatch io channel must relinquish localSocket before it is
  // closed: closing a descriptor that a dispatch source still monitors
  // crashes libdispatch with EV_VANISHED. The writer is wound down first so
  // outbound bytes flush before responses stop being read; its channel closes
  // its own duplicated descriptor. Reader drains are time-bounded.
  private static func stopForwarding(
    inputReader: FBFileReader,
    remoteReader: FBFileReader,
    remoteWriter: FBDataConsumer & FBDataConsumerLifecycle,
    localSocket: Int32,
    logger: (any FBControlCoreLogger)?
  ) async {
    remoteWriter.consumeEndOfFile()
    try? await bridgeFBFutureVoid(remoteWriter.finishedConsuming)
    _ = try? await bridgeFBFuture(inputReader.finishedReading(withTimeout: teardownDrainTimeout))
    _ = try? await bridgeFBFuture(remoteReader.finishedReading(withTimeout: teardownDrainTimeout))
    logger?.log("Closing local socket \(localSocket)")
    close(localSocket)
  }

  private static func openLocalSocket(toRemotePort remotePort: Int, on device: any FBDeviceCommands, logger: (any FBControlCoreLogger)?) throws -> Int32 {
    guard let getConnectionID = device.calls.GetConnectionID else {
      throw FBDeviceSocketForwardingError.callUnavailable(function: "GetConnectionID")
    }
    let connectionID = getConnectionID(device.amDeviceRef)
    if connectionID <= 0 {
      throw FBDeviceSocketForwardingError.connectionIDUnavailable
    }
    logger?.log("Got connection ID \(connectionID), for device. Connecting to remote port \(remotePort)")
    var localSocket: Int32 = 0
    guard let usbMuxConnect = device.calls.USBMuxConnectByPort else {
      throw FBDeviceSocketForwardingError.callUnavailable(function: "USBMuxConnectByPort")
    }
    let status = usbMuxConnect(connectionID, Int32(UInt16(remotePort).bigEndian), &localSocket)
    if status != 0 {
      throw FBDeviceSocketForwardingError.remoteConnectionFailed(remotePort: remotePort)
    }
    logger?.log("Got local socket \(localSocket) for remote port \(remotePort)")
    return localSocket
  }
}

// MARK: - FBDevice+SocketForwardingCommands

extension FBDevice: SocketForwardingCommands {

  public func drainLocalFileInput(_ localFileDescriptorInput: Int32, localFileOutput localFileDescriptorOutput: Int32, remotePort: Int32) async throws {
    try await socketForwarding.drainLocalFileInput(localFileDescriptorInput, localFileOutput: localFileDescriptorOutput, remotePort: remotePort)
  }
}
