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
 */
@objc public final class FBSimulatorHID: NSObject {

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

  // MARK: Initializers

  private static var workQueue: DispatchQueue {
    DispatchQueue(label: "com.facebook.fbsimulatorcontrol.hid")
  }

  /**
   Creates and returns a `FBSimulatorHID` instance for the provided Simulator.
   Will fail if a HID Port could not be registered for the provided Simulator.
   Registration may need to occur prior to booting.
   */
  @objc(hidForSimulator:)
  public class func hid(for simulator: FBSimulator) -> FBFuture<FBSimulatorHID> {
    guard let clientClass = objc_lookUpClass(simulatorHIDClientClassName) else {
      return FBFuture(error: FBSimulatorError.describe("Could not look up class \(simulatorHIDClientClassName)").build())
    }
    // Allocate + initialize the runtime-only client without a link-time class reference.
    let allocated = class_createInstance(clientClass, 0) as AnyObject
    var clientError: AnyObject?
    guard
      let client = unsafeBitCast(allocated, to: SimDeviceLegacyHIDClientMessaging.self)
        .initWithDevice(simulator.device, error: &clientError)
    else {
      return FBFuture(
        error:
          FBSimulatorError
          .describe("Could not create instance of \(clientClass)")
          .caused(by: clientError as? Error)
          .build())
    }
    let indigo: FBSimulatorIndigoHID
    do {
      indigo = try FBSimulatorIndigoHID.simulatorKitHID()
    } catch {
      return FBFuture(error: error as NSError)
    }
    let mainScreenSize = simulator.device.deviceType.mainScreenSize
    let scale = simulator.device.deviceType.mainScreenScale
    let purple = FBSimulatorPurpleHID.purple()
    let hid = FBSimulatorHID(
      indigo: indigo,
      purple: purple,
      client: client,
      simulator: simulator,
      mainScreenSize: mainScreenSize,
      mainScreenScale: scale,
      queue: workQueue)
    return FBFuture(result: hid)
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
   Obtains the Reply Port for the Simulator. Must be obtained after the Simulator is booted.
   */
  @objc public func connect() -> FBFuture<NSNull> {
    guard client != nil else {
      return FBFuture(error: FBSimulatorError.describe("Cannot Connect, HID client has already been disposed of").build())
    }
    return FBFuture<NSNull>.empty()
  }

  /**
   Disconnects from the remote HID.
   */
  @objc public func disconnect() -> FBFuture<NSNull> {
    client = nil
    return FBFuture<NSNull>.empty()
  }

  // MARK: HID Manipulation

  /**
   Sends the event payload.
   */
  @objc public func sendEvent(_ data: Data) -> FBFuture<NSNull> {
    let result = FBFuture<NSNull>.onQueue(
      queue,
      resolve: { [self] () -> FBFuture<AnyObject> in
        let future = FBMutableFuture<AnyObject>()
        sendIndigoMessageData(data, completionQueue: queue) { error in
          if let error {
            _ = future.resolveWithError(error as NSError)
          } else {
            _ = future.resolve(withResult: NSNull())
          }
        }
        return future
      })
    return result
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
      throw FBSimulatorError.describe("Cannot send PurpleEvent, simulator reference is nil").build()
    }

    var lookupError: NSError?
    let purplePort = simulator.device.lookup("PurpleWorkspacePort", error: &lookupError)
    if purplePort == 0 {
      throw
        FBSimulatorError
        .describe("Could not find PurpleWorkspacePort in simulator bootstrap namespace")
        .caused(by: lookupError)
        .build()
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
      throw
        FBSimulatorError
        .describe("mach_msg to PurpleWorkspacePort \(purplePort) timed out after \(timeoutMs) ms — receive queue full, SpringBoard is likely not draining HID events: \(String(cString: mach_error_string(kr)))")
        .build()
    }
    throw
      FBSimulatorError
      .describe("mach_msg to PurpleWorkspacePort \(purplePort) failed: \(String(cString: mach_error_string(kr))) (kr=0x\(String(kr, radix: 16)))")
      .build()
  }

  /**
   Posts a Darwin notification to the simulator (e.g. shake, in-call status bar). Synchronous.
   */
  @objc(postDarwinNotification:error:)
  public func postDarwinNotification(_ notificationName: String) throws {
    guard let simulator else {
      throw FBSimulatorError.describe("Cannot post Darwin notification, simulator reference is nil").build()
    }
    try simulator.device.postDarwinNotification(notificationName)
  }

  // MARK: NSObject

  public override var description: String {
    "SimulatorKit HID \(String(describing: client))"
  }
}
