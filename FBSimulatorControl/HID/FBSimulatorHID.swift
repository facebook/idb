/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Darwin
@preconcurrency import FBControlCore
import Foundation
import ObjectiveC

/// Informal protocol for messaging the runtime-only `SimDeviceLegacyHIDClient` class.
/// That class historically lived in SimulatorKit and has since relocated (e.g. to CoreDeviceIO
/// in newer Xcodes), and is loaded on demand via dlopen by `FBSimulatorControlFrameworkLoader`.
/// We therefore never reference it as a Swift type — doing so would emit a link-time
/// `_OBJC_CLASS_$_SimDeviceLegacyClient` symbol pinned to a single framework, which breaks when
/// the class moves. Instead we look the class up by name, allocate it with `class_createInstance`,
/// and message it via `unsafeBitCast` to this protocol — mirroring exactly why the original
/// Objective-C used `objc_lookUpClass` + `id`.
@objc private protocol SimDeviceLegacyHIDClientMessaging {
  @objc(initWithDevice:error:)
  func initWithDevice(_ device: Any, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> AnyObject?

  @objc(sendWithMessage:freeWhenDone:completionQueue:completion:)
  func send(
    withMessage message: UnsafeMutableRawPointer,
    freeWhenDone: Bool,
    completionQueue: DispatchQueue,
    completion: @escaping @Sendable (Error?) -> Void)
}

/**
 The HID abstraction layer for a Simulator, providing two transport paths:

 1. Indigo (IndigoHIDRegistrationPort) — for touch, button, and keyboard events.
    Payloads are constructed by `FBSimulatorIndigoHID` and sent via `SimDeviceLegacyHIDClient`.
    Guest-side: `SimHIDVirtualServiceManager` dispatches on eventKind + target.

 2. PurpleWorkspacePort — for GSEvent-based events (e.g., device orientation changes).
    Payloads are constructed by `FBSimulatorPurpleHID` and sent via raw `mach_msg`.
    Guest-side: `GraphicsServices._PurpleEventCallback` → backboardd.

 See `Indigo.h` and `GSEvent.h` for wire format documentation.

 Message sends are serialized onto the private `queue`, so the type is `@unchecked Sendable`.
 */
@objc public final class FBSimulatorHID: NSObject, @unchecked Sendable {

  private static let simulatorHIDClientClassName = "SimulatorKit.SimDeviceLegacyHIDClient"

  /// Default Mach send timeout (in milliseconds) for the `sendPurpleEvent:` convenience wrapper.
  /// Healthy round-trips return in low single-digit milliseconds; 2000ms absorbs scheduler jitter
  /// while bounding the wedge condition where SpringBoard's PurpleWorkspacePort receive queue fills.
  private static let defaultPurpleSendTimeoutMs: mach_msg_timeout_t = 2000

  // MARK: Properties

  /// The Queue on which messages are sent to the HID Server.
  @objc public let queue: DispatchQueue
  /// The Indigo payload builder (touch, button, keyboard).
  @objc public let indigo: FBSimulatorIndigoHID
  /// The Purple/GSEvent payload builder (orientation, shake).
  @objc public let purple: FBSimulatorPurpleHID
  /// The dimensions of the main screen.
  @objc public let mainScreenSize: CGSize
  /// The scale of the main screen.
  @objc public let mainScreenScale: Float

  // Untyped on purpose: the concrete `SimDeviceLegacyHIDClient` is a runtime-only class (see
  // SimDeviceLegacyHIDClientMessaging). Messaged via unsafeBitCast to that protocol.
  private var client: AnyObject?
  private weak var simulator: FBSimulator?

  // Cached legacy-keyboard-suppression check (see `legacyKeyboardSuppressed()`).
  private let keyboardSuppressionLock = NSLock()
  private var cachedKeyboardSuppressed: Bool?

  // MARK: Initializers

  private static var workQueue: DispatchQueue {
    DispatchQueue(label: "com.facebook.fbsimulatorcontrol.hid")
  }

  /**
   Creates and returns a `FBSimulatorHID` instance for the provided Simulator.
   Will fail if a HID Port could not be registered for the provided Simulator.
   Registration may need to occur prior to booting.
   */
  public static func hid(for simulator: FBSimulator) throws -> FBSimulatorHID {
    guard let clientClass = objc_lookUpClass(simulatorHIDClientClassName) else {
      throw FBSimulatorHIDError.clientClassUnavailable(className: simulatorHIDClientClassName)
    }
    // Allocate + initialize the runtime-only client without a link-time class reference.
    let allocated = class_createInstance(clientClass, 0) as AnyObject
    var clientError: AnyObject?
    guard
      let client = unsafeBitCast(allocated, to: SimDeviceLegacyHIDClientMessaging.self)
        .initWithDevice(simulator.device, error: &clientError)
    else {
      throw FBSimulatorHIDError.clientCreationFailed(clientClass: "\(clientClass)", underlying: clientError as? Error)
    }
    let indigo = try FBSimulatorIndigoHID.simulatorKitHID()
    let mainScreenSize = simulator.device.deviceType.mainScreenSize
    let scale = simulator.device.deviceType.mainScreenScale
    let purple = FBSimulatorPurpleHID.purple()
    return FBSimulatorHID(
      indigo: indigo,
      purple: purple,
      client: client,
      simulator: simulator,
      mainScreenSize: mainScreenSize,
      mainScreenScale: scale,
      queue: workQueue)
  }

  private init(
    indigo: FBSimulatorIndigoHID,
    purple: FBSimulatorPurpleHID,
    client: AnyObject,
    simulator: FBSimulator,
    mainScreenSize: CGSize,
    mainScreenScale: Float,
    queue: DispatchQueue
  ) {
    self.indigo = indigo
    self.purple = purple
    self.client = client
    self.simulator = simulator
    self.mainScreenSize = mainScreenSize
    self.mainScreenScale = mainScreenScale
    self.queue = queue
    super.init()
  }

  // MARK: Lifecycle

  /**
   Disconnects from the remote HID.
   */
  public func disconnect() {
    client = nil
  }

  /// Whether the legacy keyboard HID service is suppressed for this HID's simulator.
  ///
  /// On Xcode 27 (CoreSimulator-1155.4) and later, the host-injected SimulatorHID disconnects the
  /// legacy `ExternalKeyboardService` while `dtuhidd` is active, so legacy keyboard events are
  /// delivered byte-correctly but produce no text (touch and the other services are unaffected).
  /// Cached for this HID's lifetime — the dominant case is a simulator already poisoned at connect
  /// time, and re-reading per key would re-walk the host process tree on every keystroke.
  func legacyKeyboardSuppressed() -> Bool {
    keyboardSuppressionLock.lock()
    defer { keyboardSuppressionLock.unlock() }
    if let cachedKeyboardSuppressed {
      return cachedKeyboardSuppressed
    }
    let suppressed = computeLegacyKeyboardSuppressed()
    cachedKeyboardSuppressed = suppressed
    return suppressed
  }

  private func computeLegacyKeyboardSuppressed() -> Bool {
    // Only CoreSimulator-1155.4+ (Xcode 27) ships the dtuhidd suppression machinery; older
    // toolchains have no `dtuhidd`, so skip the process-tree walk entirely.
    guard let version = FBSimulatorControlFrameworkLoader.loadedCoreSimulatorVersion,
      version.compare("1155.4", options: .numeric) != .orderedAscending
    else {
      return false
    }
    // `dtuhidd` runs as a child of the simulator's `launchd_sim`; its presence in the simulator's
    // process subtree is the per-simulator signal. Read host-side (the authoritative guest notify
    // state `com.apple.coredevice.dtuhidd.active` is not host-bridged).
    return simulator?.launchdSimSubprocessIdentifier(named: "dtuhidd") != nil
  }

  // MARK: HID Manipulation

  /**
   Sends the event payload, completing when the client acknowledges delivery.
   */
  public func sendEvent(_ data: Data) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async { [self] in
        sendIndigoMessageData(data, completionQueue: queue) { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
        }
      }
    }
  }

  /**
   Sends the event payload, synchronously. Callers must guarantee all calls are from the same queue.
   */
  @objc public func sendIndigoMessageData(_ data: Data, completionQueue: DispatchQueue, completion: @escaping @Sendable (Error?) -> Void) {
    // The event is delivered asynchronously. Copy the message and let the client manage its lifecycle:
    // the free of the buffer is performed by the client (freeWhenDone) and the Data frees when out of scope.
    let size = data.count
    guard let raw = malloc(size) else {
      fatalError("Failed to allocate \(size) bytes for an Indigo message")
    }
    data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      guard let base = buffer.baseAddress else { return }
      raw.copyMemory(from: base, byteCount: size)
    }
    guard let client else {
      free(raw)
      return
    }
    unsafeBitCast(client, to: SimDeviceLegacyHIDClientMessaging.self)
      .send(withMessage: raw, freeWhenDone: true, completionQueue: completionQueue, completion: completion)
  }

  /**
   Sends a raw mach message to the simulator's PurpleWorkspacePort using a default 2000ms send timeout.
   */
  @objc(sendPurpleEvent:error:)
  public func sendPurpleEvent(_ data: Data) throws {
    try sendPurpleEvent(data, timeoutMs: FBSimulatorHID.defaultPurpleSendTimeoutMs)
  }

  /**
   Sends a raw mach message to the simulator's PurpleWorkspacePort, bounded by an explicit send-side timeout.
   The `msgh_remote_port` field is patched with the PurpleWorkspacePort looked up from the simulator's
   bootstrap namespace. The send always uses `mach_msg(MACH_SEND_TIMEOUT)`; on `MACH_SEND_TIMED_OUT` the
   kernel guarantees the message is not enqueued.
   */
  @objc(sendPurpleEvent:timeoutMs:error:)
  public func sendPurpleEvent(_ data: Data, timeoutMs: mach_msg_timeout_t) throws {
    guard let simulator else {
      throw FBSimulatorHIDError.simulatorDeallocatedForPurpleEvent
    }

    var lookupError: NSError?
    let purplePort = simulator.device.lookup("PurpleWorkspacePort", error: &lookupError)
    if purplePort == 0 {
      throw FBSimulatorHIDError.purpleWorkspacePortUnavailable(underlying: lookupError)
    }

    // Copy the payload and patch msgh_remote_port with the looked-up port.
    var mutableData = data
    let kr: kern_return_t = mutableData.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> kern_return_t in
      guard let base = buffer.baseAddress else { return KERN_FAILURE }
      let header = base.assumingMemoryBound(to: mach_msg_header_t.self)
      header.pointee.msgh_remote_port = purplePort
      return mach_msg(
        header,
        MACH_SEND_MSG | MACH_SEND_TIMEOUT,
        header.pointee.msgh_size,
        0,
        mach_port_t(MACH_PORT_NULL),
        timeoutMs,
        mach_port_t(MACH_PORT_NULL))
    }

    if kr == KERN_SUCCESS {
      return
    }
    if kr == MACH_SEND_TIMED_OUT {
      throw FBSimulatorHIDError.machSendTimedOut(
        port: purplePort, timeoutMs: timeoutMs, detail: String(cString: mach_error_string(kr)))
    }
    throw FBSimulatorHIDError.machSendFailed(
      port: purplePort, detail: String(cString: mach_error_string(kr)), code: kr)
  }

  /**
   Posts a Darwin notification to the simulator (e.g. shake, in-call status bar). Synchronous.
   */
  @objc(postDarwinNotification:error:)
  public func postDarwinNotification(_ notificationName: String) throws {
    guard let simulator else {
      throw FBSimulatorHIDError.simulatorDeallocatedForDarwinNotification
    }
    try simulator.device.postDarwinNotification(notificationName)
  }

  // MARK: NSObject

  public override var description: String {
    "SimulatorKit HID \(String(describing: client))"
  }
}

// MARK: - Simulator process tree

/// Host-side `launchd_sim` process-tree queries. Kept private to the HID layer (its only consumer),
/// so it stays off the public `FBSimulator` API and can be inlined further if needed.
private extension FBSimulator {

  /// The host `launchd_sim` process backing this simulator, matched by the simulator's UDID in its
  /// arguments, or `nil` if it cannot be found (e.g. the simulator is not booted).
  func launchdSimProcess(using fetcher: FBProcessFetcher = FBProcessFetcher()) -> FBProcessInfo? {
    fetcher.processes(withProcessName: "launchd_sim").first { process in
      process.arguments.contains { $0.contains(udid) }
    }
  }

  /// The process identifier of a subprocess of this simulator's `launchd_sim` whose name contains
  /// `name`, or `nil` if there is none. A purely host-side query of the simulator's process subtree.
  func launchdSimSubprocessIdentifier(named name: String, using fetcher: FBProcessFetcher = FBProcessFetcher()) -> pid_t? {
    guard let launchdSim = launchdSimProcess(using: fetcher) else {
      return nil
    }
    let identifier = fetcher.subprocess(of: launchdSim.processIdentifier, withName: name)
    return identifier > 0 ? identifier : nil
  }
}

// MARK: - Loaded CoreSimulator version

/// Kept private to the HID layer (its only consumer): the loaded framework version, read here rather
/// than swiftifying the Objective-C framework loader (a separate concern).
private extension FBSimulatorControlFrameworkLoader {

  /// The version of the CoreSimulator framework actually loaded in-process (e.g. `"1155.4"`), read
  /// from the bundle that vends `SimDevice`, or `nil` if it is not loaded. CoreSimulator is a system
  /// framework that the Xcode installer overwrites, so the loaded framework can differ from the
  /// selected Xcode; behaviour gated on a CoreSimulator version must consult this, not the Xcode one.
  static var loadedCoreSimulatorVersion: String? {
    guard let simDeviceClass = NSClassFromString("SimDevice") else {
      return nil
    }
    return Bundle(for: simDeviceClass).infoDictionary?["CFBundleVersion"] as? String
  }
}
