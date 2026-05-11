/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

// MARK: - FBDeviceLogOperation

@objc(FBDeviceLogOperation)
public class FBDeviceLogOperation: NSObject, FBLogOperation {
  public let consumer: any FBDataConsumer
  private let readCompleted: FBFuture<NSNull>
  private let serviceCompleted: FBMutableFuture<NSNull>

  // MARK: Initializers

  init(
    consumer: any FBDataConsumer,
    readCompleted: FBFuture<NSNull>,
    serviceCompleted: FBMutableFuture<NSNull>
  ) {
    self.consumer = consumer
    self.readCompleted = readCompleted
    self.serviceCompleted = serviceCompleted
    super.init()
  }

  // MARK: FBiOSTargetOperation

  public var completed: FBFuture<NSNull> {
    return unsafeBitCast(serviceCompleted, to: FBFuture<NSNull>.self)
  }
}

// MARK: - FBDeviceLogCommands

@objc(FBDeviceLogCommands)
public class FBDeviceLogCommands: NSObject, FBLogCommands {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBLogCommands

  public func tailLog(_ arguments: [String], consumer: any FBDataConsumer) -> FBFuture<any FBLogOperation> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    if !arguments.isEmpty {
      let unsupportedArgumentsMessage = "[FBDeviceLogCommands][rdar://38452839] Unsupported arguments: \(arguments)"
      if let data = unsupportedArgumentsMessage.data(using: .utf8) {
        consumer.consumeData(data)
      }
      device.logger?.log(unsupportedArgumentsMessage)
    }
    let queue = device.asyncQueue
    let readQueue = DispatchQueue(label: "com.facebook.fbdevicecontrol.device_log_consumer")
    return
      device
      .startService("com.apple.syslog_relay")
      .onQueue(
        queue,
        enter: { connection, teardown -> Any in
          let reader = connection.readFromConnectionWriting(to: consumer, on: readQueue)
          reader.startReading()
          let readCompleted = reader.finishedReading(withTimeout: .infinity).mapReplace(NSNull()) as! FBFuture<NSNull>
          return FBDeviceLogOperation(
            consumer: consumer,
            readCompleted: readCompleted,
            serviceCompleted: teardown
          )
        }) as! FBFuture<any FBLogOperation>
  }
}

// MARK: - FBDevice+AsyncLogCommands

extension FBDevice: AsyncLogCommands {

  public func tailLog(arguments: [String], consumer: any FBDataConsumer) async throws -> any AsyncLogOperation {
    let operation = try await bridgeFBFuture(logCommands().tailLog(arguments, consumer: consumer))
    return AsyncLogOperationBridge(operation)
  }
}
