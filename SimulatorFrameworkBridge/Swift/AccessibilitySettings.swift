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

enum DeviceSettingRead: Equatable {
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
  struct AdditionalSetting {
    let observe: (@escaping () -> Void) -> FBAXDeviceSettingMonitorOutcome
    let read: () throws -> DeviceSettingRead
  }

  private let settingName: String
  private let observe: (@escaping () -> Void) -> FBAXDeviceSettingMonitorOutcome
  private let coalescingDelay: TimeInterval
  private let maximumCoalescingDelay: TimeInterval
  private let read: () throws -> DeviceSettingRead
  private let additionalSettings: [String: AdditionalSetting]

  private let lock = NSLock()
  private var cancelled = false
  private var runLoop: CFRunLoop?

  private var observer: (any FBAXDeviceSettingMonitor)?
  private var additionalObservers: [any FBAXDeviceSettingMonitor] = []
  private var additionalRegistrationFailures: [String: DeviceSettingRead] = [:]
  private var emit: ((Data) -> Bool)?
  private var lastEnabled: Bool?
  private var lastAdditionalReads: [String: DeviceSettingRead]?
  private var trailingTimer: CFRunLoopTimer?
  private var maximumTimer: CFRunLoopTimer?
  private(set) var failed = false

  init(
    settingName: String,
    observe: @escaping (@escaping () -> Void) -> FBAXDeviceSettingMonitorOutcome,
    coalescingDelay: TimeInterval = 0.05,
    maximumCoalescingDelay: TimeInterval = 0.25,
    additionalSettings: [String: AdditionalSetting] = [:],
    read: @escaping () throws -> DeviceSettingRead
  ) {
    self.settingName = settingName
    self.observe = observe
    self.coalescingDelay = coalescingDelay
    self.maximumCoalescingDelay = maximumCoalescingDelay
    self.read = read
    self.additionalSettings = additionalSettings
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
      for (name, setting) in additionalSettings {
        guard !isCancelled else { break }
        let registration = setting.observe { [weak self] in self?.settingChanged() }
        if let monitor = registration.monitor { additionalObservers.append(monitor) }
        switch registration.status {
        case .resolved: break
        case .unavailable:
          additionalRegistrationFailures[name] = .unavailable(registration.failureReason ?? "Setting observation unavailable")
        case .failed:
          additionalRegistrationFailures[name] = .failed(registration.failureReason ?? "Setting observation failed")
        @unknown default:
          additionalRegistrationFailures[name] = .failed("Unknown setting observation status")
        }
      }
      readAndEmit()
    }
    while !isCancelled {
      CFRunLoopRunInMode(.defaultMode, 1, false)
    }
    invalidateTimers()
    observer?.invalidate()
    observer = nil
    for monitor in additionalObservers { monitor.invalidate() }
    additionalObservers.removeAll()
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
      var additional = additionalRegistrationFailures
      for (name, setting) in additionalSettings where additional[name] == nil {
        do { additional[name] = try setting.read() } catch { additional[name] = .failed(error.localizedDescription) }
      }
      guard enabled != lastEnabled || additional != lastAdditionalReads else { return }
      lastEnabled = enabled
      lastAdditionalReads = additional
      write(snapshot(enabled: enabled, additional: additional))
    case let .unavailable(message):
      fail(message, kind: .capabilityUnavailable)
    case let .failed(message):
      fail(message, kind: .readerUnavailable)
    }
  }

  private func snapshot(enabled: Bool, additional: [String: DeviceSettingRead]) -> [String: Any] {
    var envelope: [String: Any] = [
      BridgeAXWire.Envelope.ok.rawValue: true,
      BridgeAXWire.Settings.Key.event.rawValue: BridgeAXWire.Settings.Event.snapshot.rawValue,
      BridgeAXWire.Request.setting.rawValue: settingName,
      BridgeAXWire.Envelope.enabled.rawValue: enabled,
    ]
    if !additional.isEmpty {
      envelope[BridgeAXWire.Settings.Key.settings.rawValue] = additional.mapValues(Self.envelope)
    }
    return envelope
  }

  private static func envelope(_ read: DeviceSettingRead) -> [String: Any] {
    switch read {
    case let .available(enabled): return [BridgeAXWire.Envelope.ok.rawValue: true, BridgeAXWire.Envelope.enabled.rawValue: enabled]
    case let .unavailable(reason): return [BridgeAXWire.Envelope.ok.rawValue: false, BridgeAXWire.Envelope.error.rawValue: reason, BridgeAXWire.Envelope.errorKind.rawValue: BridgeAXWire.ErrorKind.capabilityUnavailable.rawValue]
    case let .failed(reason): return [BridgeAXWire.Envelope.ok.rawValue: false, BridgeAXWire.Envelope.error.rawValue: reason, BridgeAXWire.Envelope.errorKind.rawValue: BridgeAXWire.ErrorKind.readerUnavailable.rawValue]
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
    let observeAll = requestedName == "state-settings"
    guard let setting = AccessibilityDeviceSetting(rawValue: observeAll ? "reduce-motion" : requestedName) else {
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
    let additional: [AccessibilityDeviceSetting] = observeAll ? [.reduceTransparency, .buttonShapes, .increaseContrast] : []
    let additionalSettings = Dictionary(
      uniqueKeysWithValues: additional.map { setting in
        (
          setting.rawValue,
          DeviceSettingStream.AdditionalSetting(
            observe: { client.monitorDeviceSettings([NSNumber(value: setting.runtimeValue.rawValue)], handler: $0) },
            read: { try readSetting(setting, client: client) })
        )
      })
    return .stream(
      DeviceSettingStream(
        settingName: requestedName,
        observe: { client.monitorDeviceSettings([NSNumber(value: setting.runtimeValue.rawValue)], handler: $0) },
        additionalSettings: additionalSettings,
        read: { try readSetting(setting, client: client) }
      ))
  }

  private static func readSetting(_ setting: AccessibilityDeviceSetting, client: FBAXClient) throws -> DeviceSettingRead {
    let outcome = try client.enabledState(for: setting.runtimeValue)
    switch outcome.status {
    case .resolved: return .available(outcome.isEnabled)
    case .unavailable: return .unavailable(outcome.failureReason ?? "Setting unavailable")
    case .failed: return .failed(outcome.failureReason ?? "Setting read failed")
    @unknown default: return .failed("Unknown setting read status")
    }
  }

  private static func failure(_ message: String, kind: BridgeAXWire.ErrorKind) -> [String: Any] {
    [
      BridgeAXWire.Envelope.ok.rawValue: false,
      BridgeAXWire.Envelope.error.rawValue: message,
      BridgeAXWire.Envelope.errorKind.rawValue: kind.rawValue,
    ]
  }
}
