/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreFoundation
import FBSimulatorBridgeProtocol
import Foundation

#if canImport(SimulatorFrameworkBridgeRuntime)
@_implementationOnly import SimulatorFrameworkBridgeRuntime
#endif

enum DeviceSettingRead {
  case available(Bool)
  case unavailable(String)
  case failed(String)
}

/// Publishes the current value after registering its notification observer, then authoritative rereads.
///
/// Run-loop-owned state is touched only by `run`; the notification callback and cancellation reach only
/// the lock-protected run-loop reference and cancellation flag.
// SAFETY: cross-thread state is protected by `lock`; all remaining mutable state is confined to `runLoop`.
// patternlint-disable-next-line unchecked-sendable
final class DeviceSettingStream: BridgeResponseStream, @unchecked Sendable {
  private let settingName: String
  private let observe: (@escaping () -> Void) -> FBAXDeviceSettingMonitorOutcome
  private let coalescingDelay: TimeInterval
  private let maximumCoalescingDelay: TimeInterval
  private let read: () throws -> DeviceSettingRead

  private let lock = NSLock()
  private var cancelled = false
  private var runLoop: CFRunLoop?

  private var observer: (any FBAXDeviceSettingMonitor)?
  private var emit: ((Data) -> Bool)?
  private var lastEnabled: Bool?
  private var trailingTimer: CFRunLoopTimer?
  private var maximumTimer: CFRunLoopTimer?
  private(set) var failed = false

  init(
    settingName: String,
    observe: @escaping (@escaping () -> Void) -> FBAXDeviceSettingMonitorOutcome,
    coalescingDelay: TimeInterval = 0.05,
    maximumCoalescingDelay: TimeInterval = 0.25,
    read: @escaping () throws -> DeviceSettingRead
  ) {
    self.settingName = settingName
    self.observe = observe
    self.coalescingDelay = coalescingDelay
    self.maximumCoalescingDelay = maximumCoalescingDelay
    self.read = read
  }

  func run(emit: @escaping (Data) -> Bool) {
    lock.lock()
    guard !cancelled else {
      lock.unlock()
      return
    }
    let runLoop = CFRunLoopGetCurrent()
    self.runLoop = runLoop
    lock.unlock()

    self.emit = emit
    let registration = observe { [weak self] in self?.settingChanged() }
    observer = registration.monitor
    switch registration.status {
    case .resolved: break
    case .unavailable:
      fail(registration.failureReason ?? "Setting observation unavailable", kind: .capabilityUnavailable)
    case .failed:
      fail(registration.failureReason ?? "Setting observation failed", kind: .readerUnavailable)
    @unknown default:
      fail("Unknown setting observation status", kind: .readerUnavailable)
    }
    if !isCancelled {
      readAndEmit()
    }
    while !isCancelled {
      CFRunLoopRunInMode(.defaultMode, 1, false)
    }
    invalidateTimers()
    observer?.invalidate()
    observer = nil
    self.emit = nil
    lock.lock()
    self.runLoop = nil
    lock.unlock()
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let runLoop = runLoop
    lock.unlock()
    if let runLoop {
      CFRunLoopStop(runLoop)
    }
  }

  private var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  private func settingChanged() {
    lock.lock()
    let runLoop = cancelled ? nil : runLoop
    lock.unlock()
    guard let runLoop else { return }
    CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
      self?.scheduleReread(on: runLoop)
    }
    CFRunLoopWakeUp(runLoop)
  }

  private func scheduleReread(on runLoop: CFRunLoop) {
    guard !isCancelled else { return }
    if maximumTimer == nil {
      maximumTimer = timer(after: maximumCoalescingDelay) { [weak self] in self?.reread() }
      if let maximumTimer {
        CFRunLoopAddTimer(runLoop, maximumTimer, .defaultMode)
      }
    }
    if let trailingTimer {
      CFRunLoopTimerInvalidate(trailingTimer)
    }
    trailingTimer = timer(after: coalescingDelay) { [weak self] in self?.reread() }
    if let trailingTimer {
      CFRunLoopAddTimer(runLoop, trailingTimer, .defaultMode)
    }
  }

  private func timer(after delay: TimeInterval, handler: @escaping () -> Void) -> CFRunLoopTimer {
    CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { _ in handler() }
  }

  private func reread() {
    invalidateTimers()
    readAndEmit()
  }

  private func invalidateTimers() {
    if let trailingTimer {
      CFRunLoopTimerInvalidate(trailingTimer)
    }
    if let maximumTimer {
      CFRunLoopTimerInvalidate(maximumTimer)
    }
    trailingTimer = nil
    maximumTimer = nil
  }

  private func readAndEmit() {
    guard !isCancelled else { return }
    let result: DeviceSettingRead
    do {
      result = try read()
    } catch {
      return fail("device setting \(settingName) read failed: \(error.localizedDescription)", kind: .readerUnavailable)
    }
    guard !isCancelled else { return }
    switch result {
    case let .available(enabled):
      guard enabled != lastEnabled else { return }
      lastEnabled = enabled
      write([
        BridgeAXWire.Envelope.ok.rawValue: true,
        BridgeAXWire.Settings.Key.event.rawValue: BridgeAXWire.Settings.Event.snapshot.rawValue,
        BridgeAXWire.Request.setting.rawValue: settingName,
        BridgeAXWire.Envelope.enabled.rawValue: enabled,
      ])
    case let .unavailable(message):
      fail(message, kind: .capabilityUnavailable)
    case let .failed(message):
      fail(message, kind: .readerUnavailable)
    }
  }

  private func fail(_ message: String, kind: BridgeAXWire.ErrorKind) {
    failed = true
    write([
      BridgeAXWire.Envelope.ok.rawValue: false,
      BridgeAXWire.Envelope.error.rawValue: message,
      BridgeAXWire.Envelope.errorKind.rawValue: kind.rawValue,
    ])
    finish()
  }

  private func write(_ envelope: [String: Any]) {
    guard !isCancelled, let emit else { return }
    if !emit(AccessibilityService.serializeResponse(envelope)) {
      finish()
    }
  }

  private func finish() {
    lock.lock()
    cancelled = true
    let runLoop = runLoop
    lock.unlock()
    if let runLoop {
      CFRunLoopStop(runLoop)
    }
  }
}

enum AccessibilityStreamStart {
  case stream(any BridgeResponseStream)
  case failure([String: Any])
}

extension AccessibilityService {
  static func settings(_ request: BridgeAXRequest) -> AccessibilityStreamStart? {
    guard case let .deviceSettingChanges(requestedName) = request else { return nil }
    guard let setting = AccessibilityDeviceSetting(rawValue: requestedName) else {
      return .failure(failure("unsupported device setting: \(requestedName)", kind: .badRequest))
    }
    guard setting == .reduceMotion else {
      return .failure(failure("device setting \(requestedName) does not publish changes", kind: .capabilityUnavailable))
    }

    let client: FBAXClient
    do {
      client = try FBAXClientProvider.client()
    } catch {
      return .failure(failure(error.localizedDescription, kind: .readerUnavailable))
    }
    return .stream(
      DeviceSettingStream(
        settingName: requestedName,
        observe: { client.monitorDeviceSetting(setting.runtimeValue, handler: $0) },
        read: {
          let outcome = try client.enabledState(for: setting.runtimeValue)
          switch outcome.status {
          case .resolved:
            return .available(outcome.isEnabled)
          case .unavailable:
            return .unavailable(outcome.failureReason ?? "device setting \(requestedName) is unavailable")
          case .failed:
            return .failed(outcome.failureReason ?? "device setting \(requestedName) failed")
          @unknown default:
            return .failed("device setting \(requestedName) returned an unknown status")
          }
        }
      ))
  }

  private static func failure(_ message: String, kind: BridgeAXWire.ErrorKind) -> [String: Any] {
    [
      BridgeAXWire.Envelope.ok.rawValue: false,
      BridgeAXWire.Envelope.error.rawValue: message,
      BridgeAXWire.Envelope.errorKind.rawValue: kind.rawValue,
    ]
  }
}
