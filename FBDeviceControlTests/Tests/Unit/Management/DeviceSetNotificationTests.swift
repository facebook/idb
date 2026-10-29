/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Foundation
import MobileDeviceAPI
import Testing

@Suite(.serialized)
struct DeviceSetNotificationTests {

  enum ArrivalOrder: CaseIterable, Sendable {
    case ordinaryFirst
    case restorableFirst
  }

  enum DisconnectTiming: CaseIterable, Sendable {
    case beforeUnsubscribe
    case duringUnsubscribe
  }

  enum ReplacementTiming: CaseIterable, Sendable {
    case beforeProcessing
    case duringCallback
    case updateBeforeProcessing
    case updateDuringCallback
  }

  private final class NativeRestorable: NSObject {
    let ecid: UInt = 43
    let name: String
    private let lock = NSLock()
    private var nativeState: AMRestorableDeviceState
    private var recovery = NSObject()

    var state: AMRestorableDeviceState { lock.withLock { nativeState } }
    var recoveryDevice: NSObject { lock.withLock { recovery } }

    func transition(to state: AMRestorableDeviceState, recoveryDevice: NSObject) {
      lock.withLock {
        nativeState = state
        recovery = recoveryDevice
      }
    }

    init(name: String, state: AMRestorableDeviceState) {
      self.name = name
      self.nativeState = state
    }
  }

  private struct Observation {
    let kind: String
    let identifier: String
    let name: String
    let state: TargetState
    let valueName: String?
    let backingName: String?
    let backingState: TargetState?
    let nativeReference: ObjectIdentifier?
    let recoveryReference: ObjectIdentifier?
  }

  private final class ConstructionLogger: ControlCoreLogger, Sendable {
    let name: String? = nil
    let level: ControlCoreLogLevel = .info
    private let onConstruction: @Sendable () -> Void

    init(onConstruction: @escaping @Sendable () -> Void) {
      self.onConstruction = onConstruction
    }

    func log(_ message: String) -> any ControlCoreLogger { self }
    func info() -> any ControlCoreLogger { self }
    func debug() -> any ControlCoreLogger { self }
    func error() -> any ControlCoreLogger { self }
    func withDateFormatEnabled(_ enabled: Bool) -> any ControlCoreLogger { self }

    func withName(_ name: String) -> any ControlCoreLogger {
      onConstruction()
      return self
    }
  }

  private final class Recorder: TargetSetDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedDevices: [Device] = []
    private var recordedRemovals: [Device] = []
    private var recordedObservations: [Observation] = []
    private var added: (@Sendable (String) -> Void)?
    let bothAdded = AsyncEvent<Void>()

    var devices: [Device] { lock.withLock { recordedDevices } }
    var removals: [Device] { lock.withLock { recordedRemovals } }
    var observations: [Observation] { lock.withLock { recordedObservations } }

    var onNotification: (@Sendable (String) -> Void)? {
      get { lock.withLock { added } }
      set { lock.withLock { added = newValue } }
    }

    private func observe(_ device: Device, kind: String) {
      let backing: (any TargetInfo & DeviceProtocol)? = (device.amDevice as (any TargetInfo & DeviceProtocol)?) ?? device.restorableDevice
      let native = device.amDeviceRef ?? device.restorableDevice?.restorableDevice
      let observation = Observation(
        kind: kind, identifier: device.uniqueIdentifier, name: device.name,
        state: device.state, valueName: device.allValues[DeviceKey.deviceName.rawValue] as? String,
        backingName: backing?.allValues[DeviceKey.deviceName.rawValue] as? String,
        backingState: backing?.state,
        nativeReference: native.map { ObjectIdentifier($0 as AnyObject) },
        recoveryReference: device.recoveryModeDeviceRef.map { ObjectIdentifier($0 as AnyObject) })
      lock.withLock { recordedObservations.append(observation) }
    }

    func targetAdded(_ targetInfo: any TargetInfo, in targetSet: any TargetSet) {
      guard let device = targetInfo as? Device else { return }
      onNotification?(device.uniqueIdentifier)
      observe(device, kind: "added")
      let count = lock.withLock {
        recordedDevices.append(device)
        return recordedDevices.count
      }
      if count == 2 { bothAdded.happen() }
    }

    func targetRemoved(_ targetInfo: any TargetInfo, in targetSet: any TargetSet) {
      guard let device = targetInfo as? Device else { return }
      observe(device, kind: "removed")
      lock.withLock { recordedRemovals.append(device) }
    }
    func targetUpdated(_ targetInfo: any TargetInfo, in targetSet: any TargetSet) {
      guard let device = targetInfo as? Device else { return }
      onNotification?(device.uniqueIdentifier)
      observe(device, kind: "updated")
    }
  }

  private final class Notifications: @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
      let lock = NSLock()
      var current: Notifications?
    }

    private static let registry = Registry()
    static var current: Notifications? {
      get { registry.lock.withLock { registry.current } }
      set { registry.lock.withLock { registry.current = newValue } }
    }

    private let lock = NSLock()
    private var ordinaryCallback: AMDeviceNotificationCallback?
    private var ordinaryContext: UnsafeMutableRawPointer?
    private var restorableCallback: AMRestorableDeviceNotificationCallback?
    private var restorableContext: UnsafeMutableRawPointer?
    private let ordinary = FakeAMDevice()
    private let restorable = NSObject()
    private var overlap: ArrivalOrder?
    private var construction: (@Sendable () -> Void)?
    private var unsubscribeResult: Int32 = 0
    private var unsubscribe: (@Sendable () -> Void)?
    private var release: (@Sendable () -> Void)?
    private var retains = 0
    private var releases = 0
    private let retainsNativeReferences: Bool

    var pendingOverlap: ArrivalOrder? {
      get { lock.withLock { overlap } }
      set { lock.withLock { overlap = newValue } }
    }

    var onConstruction: (@Sendable () -> Void)? {
      get { lock.withLock { construction } }
      set { lock.withLock { construction = newValue } }
    }

    var unsubscribeStatus: Int32 {
      get { lock.withLock { unsubscribeResult } }
      set { lock.withLock { unsubscribeResult = newValue } }
    }

    var onUnsubscribe: (@Sendable () -> Void)? {
      get { lock.withLock { unsubscribe } }
      set { lock.withLock { unsubscribe = newValue } }
    }

    var onRelease: (@Sendable () -> Void)? {
      get { lock.withLock { release } }
      set { lock.withLock { release = newValue } }
    }

    var referenceCounts: [Int] { lock.withLock { [retains, releases] } }

    init(retainsNativeReferences: Bool = false) {
      self.retainsNativeReferences = retainsNativeReferences
      ordinary.values[DeviceKey.uniqueChipID.rawValue] = NSNumber(value: 42)
    }

    func onConnect(_ callback: @escaping @Sendable () -> Void) {
      ordinary.onConnect = callback
    }

    var calls: AMDCalls {
      var calls = ordinary.calls
      calls.CopyValue = { ref, _, key in
        guard let device = ref as? FakeAMDevice else { return nil }
        let value: AnyObject?
        if let key = key as String? {
          value = device.values[key] as AnyObject?
        } else {
          value = device.values as NSDictionary
        }
        guard let value else { return nil }
        return unsafeBitCast(Unmanaged.passRetained(value), to: Unmanaged<CFString>.self)
      }
      calls.Retain = { ref in
        if let current = Notifications.current { current.lock.withLock { current.retains += 1 } }
        if let ref, Notifications.current?.retainsNativeReferences == true { _ = Unmanaged.passRetained(ref) }
      }
      calls.Release = { ref in
        if let current = Notifications.current { current.lock.withLock { current.releases += 1 } }
        Notifications.current?.onRelease?()
        if let ref, Notifications.current?.retainsNativeReferences == true { Unmanaged.passUnretained(ref).release() }
      }
      calls.NotificationSubscribe = { callback, _, _, context, subscription in
        if let current = Notifications.current {
          current.lock.withLock {
            current.ordinaryCallback = callback
            current.ordinaryContext = context
          }
        }
        subscription?.pointee = context
        return 0
      }
      calls.NotificationUnsubscribe = { _ in
        guard let current = Notifications.current else { return 0 }
        current.onUnsubscribe?()
        return current.unsubscribeStatus
      }
      calls.RestorableDeviceRegisterForNotifications = { callback, context, _, _ in
        if let current = Notifications.current {
          current.lock.withLock {
            current.restorableCallback = callback
            current.restorableContext = context
          }
        }
        return 1
      }
      calls.RestorableDeviceUnregisterForNotifications = { _ in 0 }
      calls.RestorableDeviceGetECID = { ref in (ref as? NativeRestorable)?.ecid ?? 42 }
      calls.RestorableDeviceGetState = { ref in
        return (ref as? NativeRestorable)?.state.rawValue ?? AMRestorableDeviceState.bootedOS.rawValue
      }
      calls.RestorableDeviceGetRecoveryModeDevice = { ref in
        guard let device = ref as? NativeRestorable else { return nil }
        return Unmanaged.passUnretained(device.recoveryDevice as CFTypeRef)
      }
      calls.RestorableDeviceGetChipID = { _ in 0 }
      calls.RestorableDeviceGetDeviceClass = { _ in 0 }
      calls.RestorableDeviceGetLocationID = { _ in 0 }
      calls.RestorableDeviceCopySerialNumber = { _ in nil }
      calls.RestorableDeviceCopyUserFriendlyName = { ref in
        guard let device = ref as? NativeRestorable else { return nil }
        return Unmanaged.passRetained(device.name as CFString)
      }
      calls.RestorableDeviceCopyProductString = { _ in nil }
      return calls
    }

    func deliver(_ first: ArrivalOrder) {
      switch first {
      case .ordinaryFirst: deliverOrdinary(status: .connected)
      case .restorableFirst: deliverRestorable(restorable)
      }
    }

    func deliverOrdinary(status: AMDeviceNotificationType, device: FakeAMDevice? = nil) {
      let (callback, context) = lock.withLock { (ordinaryCallback, ordinaryContext) }
      var notification = AMDeviceNotification(amDevice: Unmanaged.passUnretained(device ?? ordinary), status: status)
      withUnsafeMutablePointer(to: &notification) { callback?($0, context) }
    }

    func deliverRestorable(_ device: NSObject, status: AMRestorableDeviceNotificationType = .connected) {
      let (callback, context) = lock.withLock { (restorableCallback, restorableContext) }
      callback?(device, status, context)
    }

    func deliverOverlap() {
      let (onConstruction, pendingOverlap) = lock.withLock {
        let pending = (construction, overlap)
        construction = nil
        overlap = nil
        return pending
      }
      onConstruction?()
      if let pendingOverlap {
        deliver(pendingOverlap == .ordinaryFirst ? .restorableFirst : .ordinaryFirst)
      }
    }

    func deliverExpiredOrdinaryDisconnect() {
      let reference: Unmanaged<AnyObject> = autoreleasepool {
        let expired = NSObject()
        return Unmanaged.passUnretained(expired)
      }
      let (callback, context) = lock.withLock { (ordinaryCallback, ordinaryContext) }
      var notification = AMDeviceNotification(amDevice: reference, status: .disconnected)
      withUnsafeMutablePointer(to: &notification) { callback?($0, context) }
    }
  }

  @Test(arguments: ArrivalOrder.allCases)
  func overlappingNotificationsKeepOneDevice(first: ArrivalOrder) async throws {
    try await checkDeviceIdentity(first: first, overlap: true)
  }

  @Test(arguments: ArrivalOrder.allCases, ReplacementTiming.allCases)
  func deferredNotificationsKeepTheirValues(source: ArrivalOrder, timing: ReplacementTiming) throws {
    let updates = timing == .updateBeforeProcessing || timing == .updateDuringCallback
    let duringCallback = timing == .duringCallback || timing == .updateDuringCallback
    let notifications = Notifications()
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let blocked = NotificationTestBarrier()
    let active = NotificationTestBarrier()
    let finished = DispatchSemaphore(value: 0)
    let logger = ConstructionLogger { notifications.deliverOverlap() }
    let managerLogger = ControlCoreGlobalConfiguration.defaultLogger
    let ordinaryManager = AMDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: managerLogger)
    let restorableManager = AMRestorableDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: managerLogger)
    let recorder = Recorder()
    let set = DeviceSet(
      amDeviceManager: ordinaryManager, restorableDeviceManager: restorableManager,
      logger: logger, delegate: recorder)
    try ordinaryManager.startListening()
    defer { try? ordinaryManager.stopListening() }
    try restorableManager.startListening()
    defer { try? restorableManager.stopListening() }

    let ordinary = ["Initial", "First", "Second", "Third"].map { name in
      let device = FakeAMDevice()
      device.values[DeviceKey.uniqueChipID.rawValue] = NSNumber(value: 43)
      device.values[DeviceKey.deviceName.rawValue] = name
      return device
    }
    let restorable = [
      NativeRestorable(name: "Initial", state: .bootedOS),
      NativeRestorable(name: "First", state: .recovery),
      NativeRestorable(name: "Second", state: .DFU),
      NativeRestorable(name: "Third", state: .restoreOS),
    ]
    func deliver(_ index: Int, disconnect: Bool = false) {
      switch source {
      case .ordinaryFirst:
        notifications.deliverOrdinary(status: disconnect ? .disconnected : .connected, device: ordinary[index])
      case .restorableFirst:
        notifications.deliverRestorable(restorable[index], status: disconnect ? .disconnected : .connected)
      }
    }
    func update() {
      let target: any TargetInfo =
        source == .ordinaryFirst
        ? ordinaryManager.currentDeviceList[0] : restorableManager.currentDeviceList[0]
      set.targetUpdated(target, in: source == .ordinaryFirst ? ordinaryManager : restorableManager)
    }

    if updates {
      deliver(0)
      if source == .ordinaryFirst {
        ordinaryManager.delegate = nil
      } else {
        restorableManager.delegate = nil
      }
    }
    if duringCallback {
      recorder.onNotification = { identifier in
        if identifier == "43" { active.block() }
      }
    }
    notifications.onConstruction = { blocked.block() }

    DispatchQueue.global().async {
      notifications.deliver(source == .ordinaryFirst ? .restorableFirst : .ordinaryFirst)
      finished.signal()
    }
    defer {
      blocked.release()
      active.release()
    }
    try #require(blocked.waitUntilBlocked())
    deliver(1)
    if updates { update() }
    let wrapper: AnyObject? =
      source == .ordinaryFirst
      ? ordinaryManager.currentDeviceList.first : restorableManager.currentDeviceList.first
    if duringCallback {
      blocked.release()
      try #require(active.waitUntilBlocked())
    }
    deliver(2)
    if updates {
      update()
      if source == .ordinaryFirst {
        ordinaryManager.delegate = set
      } else {
        restorableManager.delegate = set
      }
    }
    deliver(2, disconnect: true)
    deliver(3)
    let replacement: AnyObject? =
      source == .ordinaryFirst
      ? ordinaryManager.currentDeviceList.first : restorableManager.currentDeviceList.first
    #expect(wrapper === replacement)
    blocked.release()
    active.release()
    try #require(finished.wait(timeout: .now() + 5) == .success)
    #expect(blocked.wasReleased)
    #expect(active.wasReleased)

    let observations = Array(recorder.observations.filter { $0.identifier == "43" }.dropFirst(updates ? 1 : 0))
    #expect(observations.map(\.kind) == [updates ? "updated" : "added", updates ? "updated" : "added", "removed", "added"])
    let names =
      source == .ordinaryFirst
      ? ["First", "Second", "Second", "Third"] : Array(repeating: updates ? "Initial" : "First", count: 4)
    #expect(observations.map(\.name) == names)
    #expect(observations.map(\.valueName) == names.map(Optional.some))
    let states: [TargetState] =
      source == .ordinaryFirst
      ? Array(repeating: .booted, count: 4) : [.recovery, .DFU, .DFU, .restoreOS]
    #expect(observations.map(\.state) == states)
    #expect(observations.map(\.backingName) == ["First", "Second", nil, "Third"])
    #expect(observations.map(\.backingState) == [states[0], states[1], nil, states[3]])
    let native: [NSObject] = source == .ordinaryFirst ? ordinary : restorable
    #expect(
      observations.map(\.nativeReference) == [
        ObjectIdentifier(native[1]), ObjectIdentifier(native[2]), nil, ObjectIdentifier(native[3]),
      ])
    let recovery: [ObjectIdentifier?] =
      source == .ordinaryFirst
      ? Array(repeating: nil, count: 4)
      : [
        ObjectIdentifier(restorable[1].recoveryDevice), ObjectIdentifier(restorable[2].recoveryDevice),
        nil, ObjectIdentifier(restorable[3].recoveryDevice),
      ]
    #expect(observations.map(\.recoveryReference) == recovery)
    let device = try #require(set.allDevices.first { $0.uniqueIdentifier == "43" })
    #expect(recorder.devices.filter { $0.uniqueIdentifier == "43" }.allSatisfy { $0 === device })
    #expect(recorder.removals.first === device)
  }

  @Test
  func ordinaryNotificationsReuseAndReleaseTheirConnection() throws {
    let notifications = Notifications(retainsNativeReferences: true)
    Notifications.current = notifications
    defer { Notifications.current = nil }
    weak var native: FakeAMDevice?
    weak var backing: MobileDevice?
    try autoreleasepool {
      let logger = ControlCoreGlobalConfiguration.defaultLogger
      let manager = AMDeviceManager(
        calls: notifications.calls, work: .main, asyncQueue: .main, ecidFilter: nil, logger: logger)
      let restorableManager = AMRestorableDeviceManager(
        calls: notifications.calls, work: .main, asyncQueue: .main, ecidFilter: nil, logger: logger)
      let set = DeviceSet(
        amDeviceManager: manager, restorableDeviceManager: restorableManager, logger: logger, delegate: nil)
      try manager.startListening()
      defer { try? manager.stopListening() }
      let first = FakeAMDevice()
      first.values[DeviceKey.uniqueChipID.rawValue] = NSNumber(value: 43)
      native = first
      notifications.deliverOrdinary(status: .connected, device: first)
      backing = try #require(set.allDevices.first?.amDevice)
      notifications.deliverOrdinary(status: .paired, device: first)
      #expect(set.allDevices.first?.amDevice === backing)
      let second = FakeAMDevice()
      second.values[DeviceKey.uniqueChipID.rawValue] = NSNumber(value: 43)
      notifications.deliverOrdinary(status: .connected, device: second)
    }
    #expect(backing == nil)
    #expect(native == nil)
    let counts = notifications.referenceCounts
    #expect(counts[0] == counts[1])
  }

  @Test
  func restorableNotificationsCaptureStateBeforeManagerQueue() throws {
    let notifications = Notifications()
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let logger = ControlCoreGlobalConfiguration.defaultLogger
    let ordinaryManager = AMDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main, ecidFilter: nil, logger: logger)
    let manager = AMRestorableDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main, ecidFilter: nil, logger: logger)
    let recorder = Recorder()
    let set = DeviceSet(
      amDeviceManager: ordinaryManager, restorableDeviceManager: manager, logger: logger, delegate: recorder)
    try manager.startListening()
    defer { try? manager.stopListening() }
    let barrier = NotificationTestBarrier()
    let finished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      manager.notifications.enqueue { barrier.block() }
      finished.signal()
    }
    defer { barrier.release() }
    try #require(barrier.waitUntilBlocked())
    let native = NativeRestorable(name: "Device", state: .recovery)
    let firstRecovery = native.recoveryDevice
    notifications.deliverRestorable(native)
    let secondRecovery = NSObject()
    native.transition(to: .DFU, recoveryDevice: secondRecovery)
    notifications.deliverRestorable(native)
    #expect(manager.currentDeviceList.isEmpty)
    #expect(recorder.observations.isEmpty)
    barrier.release()
    try #require(finished.wait(timeout: .now() + 5) == .success)
    #expect(barrier.wasReleased)
    #expect(recorder.observations.map(\.state) == [.recovery, .DFU])
    #expect(recorder.observations.map(\.backingState) == [.recovery, .DFU])
    #expect(recorder.observations.map(\.nativeReference) == Array(repeating: ObjectIdentifier(native), count: 2))
    #expect(recorder.observations.map(\.recoveryReference) == [ObjectIdentifier(firstRecovery), ObjectIdentifier(secondRecovery)])
    #expect(set.allDevices.count == 1)
  }

  @Test(arguments: ArrivalOrder.allCases)
  func sequentialNotificationsKeepOneDevice(first: ArrivalOrder) async throws {
    try await checkDeviceIdentity(first: first, overlap: false)
  }

  @Test(arguments: ArrivalOrder.allCases)
  func concurrentNotificationsKeepOneDevice(first: ArrivalOrder) throws {
    let notifications = Notifications()
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let barrier = NotificationTestBarrier()
    let firstFinished = DispatchSemaphore(value: 0)
    notifications.onConstruction = {
      barrier.block()
    }
    let logger = ConstructionLogger { notifications.deliverOverlap() }
    let managerLogger = ControlCoreGlobalConfiguration.defaultLogger
    let ordinaryManager = AMDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: managerLogger)
    let restorableManager = AMRestorableDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: managerLogger)
    let recorder = Recorder()
    let set = DeviceSet(
      amDeviceManager: ordinaryManager, restorableDeviceManager: restorableManager,
      logger: logger, delegate: recorder)
    try ordinaryManager.startListening()
    defer { try? ordinaryManager.stopListening() }
    try restorableManager.startListening()
    defer { try? restorableManager.stopListening() }

    DispatchQueue.global().async {
      notifications.deliver(first)
      firstFinished.signal()
    }
    defer { barrier.release() }
    try #require(barrier.waitUntilBlocked())
    notifications.deliver(first == .ordinaryFirst ? .restorableFirst : .ordinaryFirst)
    #expect(recorder.devices.isEmpty)
    barrier.release()
    try #require(firstFinished.wait(timeout: .now() + 5) == .success)
    #expect(barrier.wasReleased)

    let device = try #require(set.allDevices.first)
    #expect(set.allDevices.count == 1)
    #expect(recorder.devices.count == 2)
    #expect(recorder.devices.allSatisfy { $0 === device })
    #expect(device.amDevice != nil)
    #expect(device.restorableDevice != nil)
  }

  @Test(arguments: [AMDeviceNotificationType.connected, .paired], [false, true])
  func pendingOrdinaryReferenceIsReleased(status: AMDeviceNotificationType, discardPending: Bool) throws {
    let notifications = Notifications(retainsNativeReferences: true)
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let barrier = NotificationTestBarrier()
    let firstFinished = DispatchSemaphore(value: 0)
    notifications.onConnect {
      barrier.block()
    }
    let manager = AMDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: "another-device", logger: ControlCoreGlobalConfiguration.defaultLogger)
    try manager.startListening()
    defer { try? manager.stopListening() }
    DispatchQueue.global().async {
      notifications.deliver(.ordinaryFirst)
      firstFinished.signal()
    }
    defer { barrier.release() }
    try #require(barrier.waitUntilBlocked())
    notifications.deliverOrdinary(status: status)
    #expect(notifications.referenceCounts == [2, 0])
    if discardPending {
      try manager.stopListening()
      #expect(notifications.referenceCounts == [2, 1])
    }
    barrier.release()
    try #require(firstFinished.wait(timeout: .now() + 5) == .success)
    #expect(barrier.wasReleased)
    #expect(notifications.referenceCounts == [2, 2])
  }

  @Test(arguments: [false, true])
  func pendingRestorableReferenceIsReleased(discardPending: Bool) throws {
    let notifications = Notifications()
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let barrier = NotificationTestBarrier()
    let firstFinished = DispatchSemaphore(value: 0)
    let manager = AMRestorableDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: "another-device", logger: ControlCoreGlobalConfiguration.defaultLogger)
    try manager.startListening()
    defer { try? manager.stopListening() }
    DispatchQueue.global().async {
      manager.notifications.enqueue { barrier.block() }
      firstFinished.signal()
    }
    defer { barrier.release() }
    try #require(barrier.waitUntilBlocked())
    weak var pendingDevice: NSObject?
    autoreleasepool {
      let device = NSObject()
      pendingDevice = device
      notifications.deliverRestorable(device)
    }
    #expect(pendingDevice != nil)
    if discardPending {
      try manager.stopListening()
      #expect(pendingDevice == nil)
    }
    barrier.release()
    try #require(firstFinished.wait(timeout: .now() + 5) == .success)
    #expect(barrier.wasReleased)
    #expect(pendingDevice == nil)
  }

  @Test(arguments: DisconnectTiming.allCases)
  func failedUnsubscribePreservesPendingDisconnect(timing: DisconnectTiming) async throws {
    let notifications = Notifications()
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let manager = AMDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: ControlCoreGlobalConfiguration.defaultLogger)
    let restorableManager = AMRestorableDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: ControlCoreGlobalConfiguration.defaultLogger)
    let recorder = Recorder()
    let set = DeviceSet(
      amDeviceManager: manager, restorableDeviceManager: restorableManager,
      logger: ControlCoreGlobalConfiguration.defaultLogger, delegate: recorder)
    try manager.startListening()
    defer {
      notifications.onUnsubscribe = nil
      notifications.unsubscribeStatus = 0
      try? manager.stopListening()
    }
    notifications.deliver(.ordinaryFirst)
    let attached = try #require(set.allDevices.first)
    #expect(manager.currentDeviceList.count == 1)

    let barrier = NotificationTestBarrier()
    let entered = AsyncEvent<Void>()
    let finished = AsyncEvent<Void>()
    notifications.onConnect {
      entered.happen()
      barrier.block()
    }
    DispatchQueue.global().async {
      notifications.deliverOrdinary(status: .paired)
      finished.happen()
    }
    defer { barrier.release() }
    try await entered.wait(timeout: 5, waitingFor: "active notification handler")
    switch timing {
    case .beforeUnsubscribe:
      notifications.deliverOrdinary(status: .disconnected)
    case .duringUnsubscribe:
      notifications.onUnsubscribe = {
        notifications.deliverOrdinary(status: .disconnected)
      }
    }
    notifications.unsubscribeStatus = -1
    #expect(throws: AMDeviceManagerError.self) { try manager.stopListening() }
    #expect(manager.currentDeviceList.count == 1)
    #expect(recorder.removals.isEmpty)

    barrier.release()
    try await finished.wait(timeout: 5, waitingFor: "notification queue to drain")
    #expect(barrier.wasReleased)
    #expect(manager.currentDeviceList.isEmpty)
    #expect(set.allDevices.isEmpty)
    #expect(recorder.removals.count == 1)
    #expect(recorder.removals.first === attached)
  }

  @Test
  func failedUnsubscribeKeepsNotificationsEnabled() throws {
    let notifications = Notifications()
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let manager = AMDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: ControlCoreGlobalConfiguration.defaultLogger)
    try manager.startListening()
    defer {
      notifications.unsubscribeStatus = 0
      try? manager.stopListening()
    }
    notifications.unsubscribeStatus = -1
    #expect(throws: AMDeviceManagerError.self) { try manager.stopListening() }
    notifications.deliver(.ordinaryFirst)
    #expect(manager.currentDeviceList.count == 1)
    notifications.unsubscribeStatus = 0
    try manager.stopListening()
    try manager.startListening()
    notifications.deliver(.ordinaryFirst)
    #expect(manager.currentDeviceList.count == 1)
  }

  @Test
  func unregisterDiscardsPendingNotificationsAndCanResume() throws {
    let notifications = Notifications()
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let logger = ConstructionLogger { notifications.deliverOverlap() }
    let managerLogger = ControlCoreGlobalConfiguration.defaultLogger
    let ordinaryManager = AMDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: managerLogger)
    let restorableManager = AMRestorableDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: managerLogger)
    let recorder = Recorder()
    let set = DeviceSet(
      amDeviceManager: ordinaryManager, restorableDeviceManager: restorableManager,
      logger: logger, delegate: recorder)
    try ordinaryManager.startListening()
    defer { try? ordinaryManager.stopListening() }
    notifications.onConstruction = {
      notifications.deliver(.ordinaryFirst)
      try? ordinaryManager.stopListening()
    }

    notifications.deliver(.ordinaryFirst)
    #expect(recorder.devices.count == 1)
    let device = try #require(set.allDevices.first)

    try ordinaryManager.startListening()
    notifications.deliver(.ordinaryFirst)
    #expect(recorder.devices.count == 2)
    #expect(recorder.devices.allSatisfy { $0 === device })
  }

  @Test
  func unknownDisconnectPreservesAttachedDevice() throws {
    let notifications = Notifications()
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let manager = AMDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: ControlCoreGlobalConfiguration.defaultLogger)
    try manager.startListening()
    defer { try? manager.stopListening() }

    notifications.deliver(.ordinaryFirst)
    let attached = try #require(manager.currentDeviceList.first)
    let counts = notifications.referenceCounts
    notifications.deliverExpiredOrdinaryDisconnect()
    #expect(notifications.referenceCounts == counts)
    #expect(manager.currentDeviceList.count == 1)
    #expect(manager.currentDeviceList.first === attached)
  }

  private final class ReleaseObserver {
    let onRelease: () -> Void
    init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }
    deinit { onRelease() }
  }

  private final class Writers: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    init(_ count: Int) { remaining = count }
    var finished: Bool { lock.withLock { remaining == 0 } }
    func finish() { lock.withLock { remaining -= 1 } }
  }

  private func ordinaryDevice(named name: String) -> FakeAMDevice {
    let device = FakeAMDevice()
    device.values[DeviceKey.uniqueChipID.rawValue] = NSNumber(value: 43)
    device.values[DeviceKey.deviceName.rawValue] = name
    return device
  }

  private func withListeningSet(
    _ body: (Notifications, AMDeviceManager, AMRestorableDeviceManager, DeviceSet) throws -> Void
  ) throws {
    let notifications = Notifications(retainsNativeReferences: true)
    Notifications.current = notifications
    defer { Notifications.current = nil }
    try autoreleasepool {
      let logger = ConstructionLogger {}
      let ordinary = AMDeviceManager(calls: notifications.calls, work: .main, asyncQueue: .main, ecidFilter: nil, logger: logger)
      let restorable = AMRestorableDeviceManager(calls: notifications.calls, work: .main, asyncQueue: .main, ecidFilter: nil, logger: logger)
      let set = DeviceSet(amDeviceManager: ordinary, restorableDeviceManager: restorable, logger: logger, delegate: nil)
      try ordinary.startListening()
      defer { try? ordinary.stopListening() }
      try restorable.startListening()
      defer { try? restorable.stopListening() }
      try body(notifications, ordinary, restorable, set)
    }
  }

  @Test
  func replacingBackingPublishesMetadataBeforeReleasingOldObjects() throws {
    let notifications = Notifications()
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let logger = ConstructionLogger {}
    let native = ordinaryDevice(named: "First")
    var old: MobileDevice? = MobileDevice(
      allValues: native.values, calls: notifications.calls,
      connectionReuseTimeout: nil, serviceReuseTimeout: nil,
      work: .main, asyncQueue: .main, logger: logger)
    old?.amDeviceRef = native
    weak var target: Device?
    let valuesReleased = DispatchSemaphore(value: 0)
    old?.allValues["releaseObserver"] = ReleaseObserver {
      #expect(target?.name == "Second")
      valuesReleased.signal()
    }
    let device = Device(amDevice: old, restorableDevice: nil, logger: logger)
    target = device
    old = nil
    let replacement = MobileDevice(
      allValues: ordinaryDevice(named: "Second").values, calls: notifications.calls,
      connectionReuseTimeout: nil, serviceReuseTimeout: nil,
      work: .main, asyncQueue: .main, logger: logger)
    let nativeReleased = DispatchSemaphore(value: 0)
    notifications.onRelease = {
      #expect(device.name == "Second")
      #expect(device.allValues[DeviceKey.deviceName.rawValue] as? String == "Second")
      #expect(device.amDevice === replacement)
      nativeReleased.signal()
    }
    defer { notifications.onRelease = nil }
    device.amDevice = replacement
    #expect(nativeReleased.wait(timeout: .now() + 5) == .success)
    #expect(valuesReleased.wait(timeout: .now() + 5) == .success)
  }

  private final class ReaderResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: (name: String?, state: TargetState?, ordinary: Bool, recovery: Bool)?
    var values: (name: String?, state: TargetState?, ordinary: Bool, recovery: Bool)? {
      get { lock.withLock { storage } }
      set { lock.withLock { storage = newValue } }
    }
  }

  @Test(arguments: ArrivalOrder.allCases)
  func readerKeepsSelectedConnectionAliveAcrossReplacement(source: ArrivalOrder) throws {
    try withListeningSet { notifications, _, _, set in
      let first = ordinaryDevice(named: "First")
      let second = ordinaryDevice(named: "Second")
      let recovery = NativeRestorable(name: "First", state: .recovery)
      let dfu = NativeRestorable(name: "Second", state: .DFU)
      if source == .ordinaryFirst {
        notifications.deliverOrdinary(status: .connected, device: first)
      } else {
        notifications.deliverRestorable(recovery)
      }
      let device = try #require(set.allDevices.first)
      weak var previous: AnyObject? = source == .ordinaryFirst ? device.amDevice : device.restorableDevice
      let barrier = NotificationTestBarrier()
      let finished = DispatchSemaphore(value: 0)
      let result = ReaderResult()
      DispatchQueue.global().async {
        autoreleasepool {
          let selected: (any TargetInfo & DeviceProtocol)? = source == .ordinaryFirst ? device.amDevice : device.restorableDevice
          barrier.block()
          result.values = (
            selected?.name, selected?.state,
            selected?.amDeviceRef === first,
            selected?.recoveryModeDeviceRef === recovery.recoveryDevice
          )
          withExtendedLifetime(selected) {}
        }
        finished.signal()
      }
      defer { barrier.release() }
      try #require(barrier.waitUntilBlocked())
      if source == .ordinaryFirst {
        notifications.deliverOrdinary(status: .connected, device: second)
      } else {
        notifications.deliverRestorable(dfu)
      }
      #expect(previous != nil)
      barrier.release()
      try #require(finished.wait(timeout: .now() + 5) == .success)
      #expect(barrier.wasReleased)
      #expect(previous == nil)
      let observed = try #require(result.values)
      #expect(observed.name == "First")
      if source == .ordinaryFirst {
        #expect(observed.ordinary)
      } else {
        #expect(observed.state == .recovery)
        #expect(observed.recovery)
      }
    }
  }

  @Test
  func backingReplacementRacesReaders() throws {
    try withListeningSet { notifications, _, _, set in
      let ordinary = [ordinaryDevice(named: "First"), ordinaryDevice(named: "Second")]
      let restorable = [NativeRestorable(name: "First", state: .recovery), NativeRestorable(name: "Second", state: .DFU)]
      notifications.deliverRestorable(restorable[0])
      notifications.deliverOrdinary(status: .connected, device: ordinary[0])
      let device = try #require(set.allDevices.first)
      let writers = Writers(1)
      DispatchQueue.concurrentPerform(iterations: 5) { worker in
        if worker == 0 {
          for round in 0..<20_000 {
            notifications.deliverRestorable(restorable[round % 2])
            if round % 4 == 0 { notifications.deliverOrdinary(status: .connected, device: ordinary[(round / 4) % 2]) }
          }
          writers.finish()
        } else {
          repeat {
            if let backing = device.restorableDevice {
              _ = backing.name
              _ = backing.state
              _ = backing.recoveryModeDeviceRef
            }
            if let backing = device.amDevice { _ = backing.amDeviceRef }
            _ = device.workQueue
            _ = device.calls
            _ = device.state
            _ = device.name
            _ = device.allValues
          } while !writers.finished
        }
      }
      #expect(set.allDevices.count == 1)
      #expect(set.allDevices.first === device)
    }
  }

  @Test
  func notificationsRaceRegistryReaders() throws {
    try withListeningSet { notifications, ordinaryManager, _, set in
      let ordinary = ordinaryDevice(named: "Ordinary")
      let restorable = NativeRestorable(name: "Recovery", state: .recovery)
      let writers = Writers(2)
      DispatchQueue.concurrentPerform(iterations: 6) { worker in
        if worker < 2 {
          for _ in 0..<1_000 {
            if worker == 0 {
              notifications.deliverOrdinary(status: .connected, device: ordinary)
              notifications.deliverOrdinary(status: .disconnected, device: ordinary)
            } else {
              notifications.deliverRestorable(restorable)
              notifications.deliverRestorable(restorable, status: .disconnected)
            }
          }
          writers.finish()
        } else {
          repeat {
            for device in set.allDevices {
              _ = device.amDevice
              _ = device.restorableDevice
              _ = device.udid
              _ = device.name
              _ = device.state
              _ = device.allValues
            }
            _ = set.device(withUDID: "fake-udid")
            _ = set.description
            _ = ordinaryManager.currentDeviceList
          } while !writers.finished
        }
      }
      #expect(set.allDevices.isEmpty)
    }
  }

  private func checkDeviceIdentity(first: ArrivalOrder, overlap: Bool) async throws {
    let notifications = Notifications()
    Notifications.current = notifications
    defer { Notifications.current = nil }
    let logger = ConstructionLogger { notifications.deliverOverlap() }
    let managerLogger = ControlCoreGlobalConfiguration.defaultLogger
    let ordinaryManager = AMDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: managerLogger)
    let restorableManager = AMRestorableDeviceManager(
      calls: notifications.calls, work: .main, asyncQueue: .main,
      ecidFilter: nil, logger: managerLogger)
    let recorder = Recorder()
    let set = DeviceSet(
      amDeviceManager: ordinaryManager, restorableDeviceManager: restorableManager,
      logger: logger, delegate: recorder)
    try ordinaryManager.startListening()
    defer { try? ordinaryManager.stopListening() }
    try restorableManager.startListening()
    defer { try? restorableManager.stopListening() }

    if overlap {
      notifications.pendingOverlap = first
      notifications.deliver(first)
    } else {
      notifications.deliver(first)
      notifications.deliver(first == .ordinaryFirst ? .restorableFirst : .ordinaryFirst)
    }
    try await recorder.bothAdded.wait(timeout: 5, waitingFor: "both device notifications")

    let device = try #require(set.allDevices.first)
    #expect(set.allDevices.count == 1)
    #expect(recorder.devices.allSatisfy { $0 === device })
    #expect(device.amDevice != nil)
    #expect(device.restorableDevice != nil)
  }
}
