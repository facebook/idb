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

/**
 The HID abstraction layer for a Simulator, providing two transport paths:

 1. Indigo (IndigoHIDRegistrationPort) — for touch, button, and keyboard events.
    Payloads are constructed by `FBSimulatorIndigoHID` and delivered by `FBSimulatorIndigoHIDClient`
    (which owns the runtime-only `SimDeviceLegacyHIDClient`).
    Guest-side: `SimHIDVirtualServiceManager` dispatches on eventKind + target.

 2. PurpleWorkspacePort — for GSEvent-based events (e.g., device orientation changes).
    Payloads are constructed by `FBSimulatorPurpleHID` and sent via raw `mach_msg`.
    Guest-side: `GraphicsServices._PurpleEventCallback` → backboardd.

 See `Indigo.h` and `GSEvent.h` for wire format documentation.

 Indigo message sends are serialized by `FBSimulatorIndigoHIDClient`, so the type is `@unchecked Sendable`.
 */
public final class FBSimulatorHID: CustomStringConvertible, @unchecked Sendable {

  /// Default Mach send timeout (in milliseconds) for the `sendPurpleEvent:` convenience wrapper.
  /// Healthy round-trips return in low single-digit milliseconds; 2000ms absorbs scheduler jitter
  /// while bounding the wedge condition where SpringBoard's PurpleWorkspacePort receive queue fills.
  private static let defaultPurpleSendTimeoutMs: mach_msg_timeout_t = 2000

  // MARK: Properties

  /// The Indigo payload builder (touch, button, keyboard).
  public let indigo: FBSimulatorIndigoHID
  /// The Purple/GSEvent payload builder (orientation, shake).
  public let purple: FBSimulatorPurpleHID
  /// The dimensions of the main screen.
  public let mainScreenSize: CGSize
  /// The scale of the main screen.
  public let mainScreenScale: Float

  /// The client that delivers Indigo message bytes to the simulator.
  private let indigoClient: FBSimulatorIndigoHIDClient
  private weak var simulator: FBSimulator?

  // Cached legacy-keyboard-suppression check (see `legacyKeyboardSuppressed()`).
  private let keyboardSuppressionLock = NSLock()
  private var cachedKeyboardSuppressed: Bool?

  // MARK: Initializers

  /**
   Creates and returns a `FBSimulatorHID` instance for the provided Simulator.
   Will fail if a HID Port could not be registered for the provided Simulator.
   Registration may need to occur prior to booting.
   */
  public static func hid(for simulator: FBSimulator) throws -> FBSimulatorHID {
    let indigoClient = try FBSimulatorIndigoHIDClient.client(for: simulator.device)
    let indigo = try FBSimulatorIndigoHID.simulatorKitHID()
    return FBSimulatorHID(
      indigo: indigo,
      purple: FBSimulatorPurpleHID.purple(),
      indigoClient: indigoClient,
      simulator: simulator,
      mainScreenSize: simulator.device.deviceType.mainScreenSize,
      mainScreenScale: simulator.device.deviceType.mainScreenScale)
  }

  private init(
    indigo: FBSimulatorIndigoHID,
    purple: FBSimulatorPurpleHID,
    indigoClient: FBSimulatorIndigoHIDClient,
    simulator: FBSimulator,
    mainScreenSize: CGSize,
    mainScreenScale: Float
  ) {
    self.indigo = indigo
    self.purple = purple
    self.indigoClient = indigoClient
    self.simulator = simulator
    self.mainScreenSize = mainScreenSize
    self.mainScreenScale = mainScreenScale
  }

  // MARK: Lifecycle

  /**
   Disconnects from the remote HID.
   */
  public func disconnect() {
    indigoClient.disconnect()
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
   Sends the Indigo event payload, completing when the client acknowledges delivery.
   */
  public func sendEvent(_ data: Data) async throws {
    try await indigoClient.send(data)
  }

  /**
   Sends a raw mach message to the simulator's PurpleWorkspacePort using a default 2000ms send timeout.
   */
  public func sendPurpleEvent(_ data: Data) throws {
    try sendPurpleEvent(data, timeoutMs: FBSimulatorHID.defaultPurpleSendTimeoutMs)
  }

  /**
   Sends a raw mach message to the simulator's PurpleWorkspacePort, bounded by an explicit send-side timeout.
   The `msgh_remote_port` field is patched with the PurpleWorkspacePort looked up from the simulator's
   bootstrap namespace. The send always uses `mach_msg(MACH_SEND_TIMEOUT)`; on `MACH_SEND_TIMED_OUT` the
   kernel guarantees the message is not enqueued.
   */
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
  public func postDarwinNotification(_ notificationName: String) throws {
    guard let simulator else {
      throw FBSimulatorHIDError.simulatorDeallocatedForDarwinNotification
    }
    try simulator.device.postDarwinNotification(notificationName)
  }

  // MARK: CustomStringConvertible

  public var description: String {
    "SimulatorKit HID"
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
