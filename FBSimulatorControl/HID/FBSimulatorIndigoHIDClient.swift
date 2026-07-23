/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import CoreSimulator
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
 Owns the runtime-only SimulatorKit `SimDeviceLegacyHIDClient` and delivers Indigo message bytes to
 it (the IndigoHIDRegistrationPort transport). The concrete class is looked up by name and messaged
 via `unsafeBitCast` — it has relocated across Xcodes, so no link-time class reference is emitted.

 Message sends are serialized onto the private `queue`, so the type is `@unchecked Sendable`.
 */
final class FBSimulatorIndigoHIDClient: @unchecked Sendable {
  typealias SendImplementation = @Sendable (
    Data, DispatchQueue, @escaping @Sendable (Error?) -> Void
  ) -> Void

  private static let clientClassName = "SimulatorKit.SimDeviceLegacyHIDClient"

  /// The queue on which messages are sent to the HID server.
  private let queue: DispatchQueue
  // Untyped on purpose: the concrete `SimDeviceLegacyHIDClient` is a runtime-only class (see
  // SimDeviceLegacyHIDClientMessaging). Messaged via unsafeBitCast to that protocol.
  private var client: AnyObject?
  private var pendingSendCount = 0
  private var disconnectRequested = false
  private var invalidationReported = false
  private let onInvalidated: @Sendable () -> Void
  /// Test observation seam. Production construction uses the no-op default.
  private let onDisposed: @Sendable () -> Void
  private let sendImplementation: SendImplementation?

  /// Looks up, allocates and initializes the runtime-only HID client for the provided device.
  convenience init(
    for device: SimDevice,
    onInvalidated: @escaping @Sendable () -> Void = {}
  ) throws {
    // The HID client class lives in SimulatorKit (or CoreDeviceIO on newer Xcodes), which is
    // loaded on demand. Host applications that haven't preloaded it (unlike the companion,
    // which loads all frameworks at startup) would otherwise fail the class lookup below.
    try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(nil)
    guard let clientClass = objc_lookUpClass(Self.clientClassName) else {
      throw FBSimulatorHIDError.clientClassUnavailable(className: Self.clientClassName)
    }
    // Allocate + initialize the runtime-only client without a link-time class reference.
    let allocated = class_createInstance(clientClass, 0) as AnyObject
    var clientError: AnyObject?
    guard
      let client = unsafeBitCast(allocated, to: SimDeviceLegacyHIDClientMessaging.self)
        .initWithDevice(device, error: &clientError)
    else {
      throw FBSimulatorHIDError.clientCreationFailed(clientClass: "\(clientClass)", underlying: clientError as? Error)
    }
    self.init(
      client: client,
      queue: DispatchQueue(label: "com.facebook.fbsimulatorcontrol.hid"),
      onInvalidated: onInvalidated)
  }

  init(
    client: AnyObject,
    queue: DispatchQueue,
    onInvalidated: @escaping @Sendable () -> Void,
    onDisposed: @escaping @Sendable () -> Void = {},
    sendImplementation: SendImplementation? = nil
  ) {
    self.client = client
    self.queue = queue
    self.onInvalidated = onInvalidated
    self.onDisposed = onDisposed
    self.sendImplementation = sendImplementation
  }

  /// Disconnects from the remote HID by releasing the client.
  func disconnect() {
    queue.async { [self] in
      disconnectRequested = true
      disposeClientIfPossible()
    }
  }

  /// Sends the message bytes, completing when the client acknowledges delivery.
  func send(_ data: Data) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async { [self] in
        sendData(data, completionQueue: queue) { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
        }
      }
    }
  }

  /// Sends the message bytes synchronously. Callers must guarantee all calls are from `queue`.
  private func sendData(_ data: Data, completionQueue: DispatchQueue, completion: @escaping @Sendable (Error?) -> Void) {
    guard !disconnectRequested, let client else {
      completion(FBSimulatorHIDError.clientDisposed)
      return
    }
    pendingSendCount += 1
    let sendCompletion: @Sendable (Error?) -> Void = { [self] error in
      pendingSendCount -= 1
      let shouldReportInvalidation: Bool
      if error != nil {
        // A completion error means this transport can no longer be trusted, but does not prove the
        // event was never delivered. Evict it for the next command instead of retrying here.
        disconnectRequested = true
        shouldReportInvalidation = !invalidationReported
        invalidationReported = true
      } else {
        shouldReportInvalidation = false
      }
      disposeClientIfPossible()
      if shouldReportInvalidation {
        onInvalidated()
      }
      completion(error)
    }
    if let sendImplementation {
      sendImplementation(data, completionQueue, sendCompletion)
      return
    }

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
    unsafeBitCast(client, to: SimDeviceLegacyHIDClientMessaging.self)
      .send(
        withMessage: raw,
        freeWhenDone: true,
        completionQueue: completionQueue,
        completion: sendCompletion)
  }

  private func disposeClientIfPossible() {
    guard disconnectRequested, pendingSendCount == 0, client != nil else {
      return
    }
    client = nil
    onDisposed()
  }
}
