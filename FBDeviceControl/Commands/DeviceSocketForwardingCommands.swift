/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public enum DeviceSocketForwardingError: Error {
  case fileDescriptorWriterFailed(fileDescriptor: Int32)
  case socketDuplicationFailed(message: String)
  case socketWriterFailed(socket: Int32)
  case callUnavailable(function: String)
  case connectionIDUnavailable
  case remoteConnectionFailed(remotePort: Int)
}

extension DeviceSocketForwardingError: LocalizedError {
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

public struct DeviceSocketForwardingCommands {
  let device: FBDevice

  public static func commands(with device: FBDevice) -> DeviceSocketForwardingCommands {
    DeviceSocketForwardingCommands(device: device)
  }

  // MARK: - Socket forwarding

  public func drainLocalFileInput(
    _ localFileDescriptorInput: Int32,
    localFileOutput localFileDescriptorOutput: Int32,
    remotePort: Int32
  ) async throws {
    var error: NSError?
    guard let localConsumer = FileWriter.asyncWriter(withFileDescriptor: localFileDescriptorOutput, closeOnEndOfFile: false, error: &error) else {
      throw error ?? DeviceSocketForwardingError.fileDescriptorWriterFailed(fileDescriptor: localFileDescriptorOutput)
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
        throw DeviceSocketForwardingError.socketDuplicationFailed(message: String(cString: strerror(errno)))
      }
      var writerError: NSError?
      guard let remoteWriter = FileWriter.asyncWriter(withFileDescriptor: writerDescriptor, closeOnEndOfFile: true, error: &writerError) else {
        close(writerDescriptor)
        close(localSocket)
        throw writerError ?? DeviceSocketForwardingError.socketWriterFailed(socket: localSocket)
      }
      let remoteReader = FileReader.reader(withFileDescriptor: localSocket, closeOnEndOfFile: false, consumer: localConsumer, logger: nil)
      let inputReader = FileReader.reader(withFileDescriptor: localFileDescriptorInput, closeOnEndOfFile: false, consumer: remoteWriter, logger: nil)
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
    inputReader: FileReader,
    remoteReader: FileReader,
    remoteWriter: FBDataConsumer & DataConsumerLifecycle,
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

  private static func openLocalSocket(toRemotePort remotePort: Int, on device: any DeviceCommands, logger: (any FBControlCoreLogger)?) throws -> Int32 {
    guard let getConnectionID = device.calls.GetConnectionID else {
      throw DeviceSocketForwardingError.callUnavailable(function: "GetConnectionID")
    }
    let connectionID = getConnectionID(device.amDeviceRef)
    if connectionID <= 0 {
      throw DeviceSocketForwardingError.connectionIDUnavailable
    }
    logger?.log("Got connection ID \(connectionID), for device. Connecting to remote port \(remotePort)")
    var localSocket: Int32 = 0
    guard let usbMuxConnect = device.calls.USBMuxConnectByPort else {
      throw DeviceSocketForwardingError.callUnavailable(function: "USBMuxConnectByPort")
    }
    let status = usbMuxConnect(connectionID, Int32(UInt16(remotePort).bigEndian), &localSocket)
    if status != 0 {
      throw DeviceSocketForwardingError.remoteConnectionFailed(remotePort: remotePort)
    }
    logger?.log("Got local socket \(localSocket) for remote port \(remotePort)")
    return localSocket
  }
}
