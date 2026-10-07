/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let EraseCallbackValueGood: Int32 = -10
private let DetectTimeout: TimeInterval = 10
private let APICallbackTimeout: TimeInterval = 15
private let OfflineTimeout: TimeInterval = 20
private let OnlineTimeout: TimeInterval = 300

// MARK: - EraseEvent

/// Something the erase waits for, which may happen before it is waited on. Only the first
/// occurrence counts.
private final class EraseEvent<Value: Sendable>: @unchecked Sendable {
  private enum State {
    case pending
    case waiting(CheckedContinuation<Value, Error>)
    case happened(Value)
  }

  private let lock = NSLock()
  private var state = State.pending

  var hasHappened: Bool {
    lock.lock()
    defer { lock.unlock() }
    switch state {
    case .happened:
      return true
    case .pending, .waiting:
      return false
    }
  }

  func happen(_ value: Value) {
    lock.lock()
    switch state {
    case .pending:
      state = .happened(value)
      lock.unlock()
    case let .waiting(continuation):
      state = .happened(value)
      lock.unlock()
      continuation.resume(returning: value)
    case .happened:
      lock.unlock()
    }
  }

  /// Returns once the event has happened. Cancelling throws `CancellationError` and leaves the event
  /// to be waited on again.
  func wait() async throws -> Value {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
        lock.lock()
        switch state {
        case let .happened(value):
          lock.unlock()
          continuation.resume(returning: value)
        case .pending where Task.isCancelled:
          lock.unlock()
          continuation.resume(throwing: CancellationError())
        case .pending:
          state = .waiting(continuation)
          lock.unlock()
        case .waiting:
          lock.unlock()
          preconditionFailure("An EraseEvent has one waiter at a time")
        }
      }
    } onCancel: {
      lock.lock()
      guard case let .waiting(continuation) = state else {
        lock.unlock()
        return
      }
      state = .pending
      lock.unlock()
      continuation.resume(throwing: CancellationError())
    }
  }

  func wait(timeout: TimeInterval, waitingFor description: String) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask {
        try await self.wait()
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw ControlCoreError.describe("Timed out after \(String(format: "%f", timeout)) seconds waiting for \(description)").build()
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else {
        preconditionFailure("The task group has two children; next() cannot be empty")
      }
      return first
    }
  }
}

// MARK: - DeviceEraseOperation

private final class DeviceEraseOperation: NSObject, TargetSetDelegate, @unchecked Sendable {

  private let udid: String
  private let calls: AMDCalls
  private let logger: any ControlCoreLogger
  private let queue: DispatchQueue
  private let deviceManager: AMRestorableDeviceManager
  private let deviceDetected = EraseEvent<Void>()
  private let deviceWentAway = EraseEvent<Void>()
  private let deviceCameBack = EraseEvent<Void>()
  private let eraseCallbackResult = EraseEvent<Int32>()

  init(device: Device, logger: any ControlCoreLogger) {
    let queue = DispatchQueue(label: "com.facebook.fbdeviceerase")
    self.udid = device.udid
    self.calls = device.calls
    self.logger = logger
    self.queue = queue
    self.deviceManager = AMRestorableDeviceManager(
      calls: device.calls,
      work: queue,
      asyncQueue: queue,
      ecidFilter: device.uniqueIdentifier,
      logger: logger
    )
    super.init()
    self.deviceManager.delegate = self
  }

  // MARK: - Erase

  func erase() async throws {
    try deviceManager.startListening()
    try await deviceDetected.wait(timeout: DetectTimeout, waitingFor: "Device to be detected the first time")
    logger.log("Device has been detected, starting erase API Call")
    let eraseCallbackValue = try await startErase()
    guard eraseCallbackValue == EraseCallbackValueGood else {
      throw DeviceEraseError.badEraseCallback(value: eraseCallbackValue, expected: EraseCallbackValueGood)
    }
    logger.log("Device API call finished, waiting for device to go offline")
    try await deviceWentAway.wait(timeout: OfflineTimeout, waitingFor: "Device to go offline")
    logger.log("Device has gone offline, waiting for it to come back online")
    try await deviceCameBack.wait(timeout: OnlineTimeout, waitingFor: "Device to come back")
  }

  /// Issues `AMSEraseDevice` on the serial queue and awaits the value delivered by
  /// the C erase callback (with a timeout).
  private func startErase() async throws -> Int32 {
    queue.async { [self] in
      let selfContext = Unmanaged.passUnretained(self).toOpaque()
      _ = calls.AMSInitialize?(0)
      let status =
        calls.AMSEraseDevice?(
          udid as CFString,
          { _, progress, context in
            guard let context else {
              return 0
            }
            let operation = Unmanaged<DeviceEraseOperation>.fromOpaque(context).takeUnretainedValue()
            operation.logger.log("Erase Callback is \(progress)")
            operation.eraseCallbackResult.happen(progress)
            return 0
          },
          selfContext
        ) ?? -1
      logger.log("AMSEraseDevice had status \(status)")
    }
    return try await eraseCallbackResult.wait(timeout: APICallbackTimeout, waitingFor: "Device erase API call to resolve")
  }

  // MARK: - TargetSetDelegate

  func targetAdded(_ targetInfo: any TargetInfo, in targetSet: any TargetSet) {
    if !deviceDetected.hasHappened {
      logger.log("Got target \(targetInfo) added for the first time")
      deviceDetected.happen(())
    } else {
      logger.log("Got target \(targetInfo) added")
      deviceCameBack.happen(())
    }
  }

  func targetRemoved(_ targetInfo: any TargetInfo, in targetSet: any TargetSet) {
    logger.log("Got target \(targetInfo) removed")
    deviceWentAway.happen(())
  }

  func targetUpdated(_ targetInfo: any TargetInfo, in targetSet: any TargetSet) {}
}

// MARK: - DeviceEraseStrategy

public enum DeviceEraseError: Error {
  case badEraseCallback(value: Int32, expected: Int32)
}

extension DeviceEraseError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .badEraseCallback(value, expected):
      return "Erase callback was \(value), not \(expected). Perhaps the device is not activated?"
    }
  }
}

final class DeviceEraseStrategy {

  static func erase(_ device: Device) async throws {
    let logger = device.logger.withName("erase_\(device.udid)")
    try await device.activate()
    let operation = DeviceEraseOperation(device: device, logger: logger)
    try await operation.erase()
    logger.log("Device erase finished successfully \(operation)")
  }
}
