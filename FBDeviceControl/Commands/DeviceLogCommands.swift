/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let syslogRelayService = "com.apple.syslog_relay"

// MARK: - DeviceLogOperation

public final class DeviceLogOperation: LogOperation {
  public let consumer: any FBDataConsumer

  /// Never resolves of its own accord: the device reaching the end of its log is not the end of the
  /// tail, and only the caller decides that. Cancelling is what invalidates the connection.
  public let completed: FBFuture<NSNull>

  init(
    consumer: any FBDataConsumer,
    connection: FBAMDServiceConnection,
    service: String,
    queue: DispatchQueue,
    logger: any FBControlCoreLogger
  ) {
    self.consumer = consumer
    let tailing = FBMutableFuture<NSNull>(name: "Tailing \(service)")
    self.completed = convertFBMutableFuture(
      tailing.onQueue(
        queue,
        respondToCancellation: {
          FBAMDevice.invalidateServiceConnection(connection, service: service, logger: logger)
          return FBFuture<NSNull>.empty()
        }
      ))
  }

  // MARK: - LogOperation

  public func waitUntilCompleted() async throws {
    try await bridgeFBFutureVoid(completed)
  }
}

// MARK: - DeviceLogCommands

public struct DeviceLogCommands: LogCommands {
  private let device: FBDevice

  public static func commands(with device: FBDevice) -> DeviceLogCommands {
    DeviceLogCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - FBLogCommands

  public func tail(arguments: [String], consumer: any FBDataConsumer) async throws -> any LogOperation {
    if !arguments.isEmpty {
      let unsupportedArgumentsMessage = "[DeviceLogCommands][rdar://38452839] Unsupported arguments: \(arguments)"
      if let data = unsupportedArgumentsMessage.data(using: .utf8) {
        consumer.consumeData(data)
      }
      device.logger.log(unsupportedArgumentsMessage)
    }
    let readQueue = DispatchQueue(label: "com.facebook.fbdevicecontrol.device_log_consumer")
    let connection = try await device.openServiceConnection(syslogRelayService)
    let reader = connection.readFromConnectionWriting(to: consumer, on: readQueue)
    reader.startReading()
    return DeviceLogOperation(
      consumer: consumer,
      connection: connection,
      service: syslogRelayService,
      queue: device.asyncQueue,
      logger: device.logger
    )
  }
}
