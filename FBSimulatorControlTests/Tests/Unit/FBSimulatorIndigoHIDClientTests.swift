/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import Testing

/// Stands in for `SimulatorKit.SimDeviceLegacyHIDClient` when its initializer raises. This is what
/// CoreSimulator does against a simulator that has been shut down underneath a live companion:
/// `-[SimDeviceIOClient ioPorts]` hits its assertion handler when the device has no IO ports left.
private final class RaisingLegacyHIDClientStub: NSObject {
  static let reason = "SimDeviceIOClient has no ioPorts"

  @objc(initWithDevice:error:)
  func initWithDevice(_ device: Any, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> AnyObject? {
    NSException(name: .internalInconsistencyException, reason: Self.reason, userInfo: nil).raise()
    return nil
  }
}

/// Stands in for `SimulatorKit.SimDeviceLegacyHIDClient` when its initializer declines by contract.
private final class NilReturningLegacyHIDClientStub: NSObject {
  static let reason = "The device is not booted"

  @objc(initWithDevice:error:)
  func initWithDevice(_ device: Any, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> AnyObject? {
    error?.pointee = NSError(
      domain: "SimDeviceLegacyHIDClient", code: 1, userInfo: [NSLocalizedDescriptionKey: Self.reason])
    return nil
  }
}

/// Stands in for a client that was built against a live device and then had it shut down underneath
/// it: the initializer succeeded, the send raises. `-[SimDeviceIOClient ioPorts]` is reached from
/// both, so a client surviving construction is no guarantee its sends will.
private final class RaisingSendLegacyHIDClientStub: NSObject {
  static let reason = "SimDeviceIOClient has no ioPorts"

  @objc(initWithDevice:error:)
  func initWithDevice(_ device: Any, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> AnyObject? {
    self
  }

  @objc(sendWithMessage:freeWhenDone:completionQueue:completion:)
  func send(
    withMessage message: UnsafeMutableRawPointer,
    freeWhenDone: Bool,
    completionQueue: DispatchQueue,
    completion: @escaping @Sendable (Error?) -> Void
  ) {
    // Deliberately does not free: a raising callee gives no way to know whether it took ownership of
    // the buffer first, which is the same bind the client is in.
    NSException(name: .internalInconsistencyException, reason: Self.reason, userInfo: nil).raise()
  }
}

/// Stands in for a client that takes the message and reports a delivery failure by contract.
private final class FailingSendLegacyHIDClientStub: NSObject {
  static let reason = "The HID server is not accepting messages"

  @objc(initWithDevice:error:)
  func initWithDevice(_ device: Any, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> AnyObject? {
    self
  }

  @objc(sendWithMessage:freeWhenDone:completionQueue:completion:)
  func send(
    withMessage message: UnsafeMutableRawPointer,
    freeWhenDone: Bool,
    completionQueue: DispatchQueue,
    completion: @escaping @Sendable (Error?) -> Void
  ) {
    if freeWhenDone {
      free(message)
    }
    completion(
      NSError(domain: "SimDeviceLegacyHIDClient", code: 2, userInfo: [NSLocalizedDescriptionKey: Self.reason]))
  }
}

/// Holds what a `@Sendable` completion was handed, which it cannot do by capturing a local.
private final class CompletionCapture: @unchecked Sendable {
  var wasCalled = false
  var error: Error?
}

@Suite("Legacy Indigo HID client")
struct FBSimulatorIndigoHIDClientTests {

  @Test("An initializer that raises surfaces the raise as a client creation failure")
  func clientInitializerRaises() throws {
    let clientClass = FBObjCRuntimeClass(RaisingLegacyHIDClientStub.self)
    var thrown: Error?
    var raised: Error?
    do {
      // The client is expected to convert the raise itself; this guard is only here so that a
      // regression fails one test rather than aborting the whole test process, which is what it
      // does to `idb_companion` — nothing between the gRPC `hid` handler and this initializer
      // catches an `NSException`.
      try FBObjCExceptionGuard.run {
        do {
          _ = try FBSimulatorIndigoHIDClient(device: NSObject(), clientClass: clientClass)
        } catch {
          thrown = error
        }
      }
    } catch {
      raised = error
    }

    #expect(raised == nil)
    let hidError = try #require(thrown as? FBSimulatorHIDError)
    guard case let .clientCreationFailed(className, underlying) = hidError else {
      Issue.record("Expected clientCreationFailed, got \(hidError)")
      return
    }
    #expect(className == NSStringFromClass(RaisingLegacyHIDClientStub.self))
    guard case let .initializerRaised(_, guardError)? = underlying as? FBObjCRuntimeClassError else {
      Issue.record("Expected initializerRaised, got \(String(describing: underlying))")
      return
    }
    #expect((guardError as NSError).domain == FBObjCExceptionGuardErrorDomain)
    #expect(guardError.localizedDescription == RaisingLegacyHIDClientStub.reason)
    // The reason the raise carried has to reach whoever asked for the HID, not stop here.
    #expect(hidError.localizedDescription.hasSuffix(RaisingLegacyHIDClientStub.reason))
  }

  @Test("An initializer that returns nil surfaces the error it wrote out")
  func clientInitializerReturnsNil() throws {
    let clientClass = FBObjCRuntimeClass(NilReturningLegacyHIDClientStub.self)
    let error = try #require(throws: FBSimulatorHIDError.self) {
      _ = try FBSimulatorIndigoHIDClient(device: NSObject(), clientClass: clientClass)
    }
    guard case let .clientCreationFailed(className, underlying) = error else {
      Issue.record("Expected clientCreationFailed, got \(error)")
      return
    }
    #expect(className == NSStringFromClass(NilReturningLegacyHIDClientStub.self))
    #expect((try #require(underlying) as NSError).localizedDescription == NilReturningLegacyHIDClientStub.reason)
  }

  @Test("A send the client reports as failed is delivered to the completion")
  func sendReportsClientFailure() throws {
    let client = try FBSimulatorIndigoHIDClient(
      device: NSObject(), clientClass: FBObjCRuntimeClass(FailingSendLegacyHIDClientStub.self))
    let capture = CompletionCapture()

    client.sendData(Data([0x01, 0x02])) {
      capture.wasCalled = true
      capture.error = $0
    }

    #expect(capture.wasCalled)
    #expect(try #require(capture.error).localizedDescription == FailingSendLegacyHIDClientStub.reason)
  }

  @Test("A send whose client raises reports the raise to the completion")
  func sendRaises() throws {
    let client = try FBSimulatorIndigoHIDClient(
      device: NSObject(), clientClass: FBObjCRuntimeClass(RaisingSendLegacyHIDClientStub.self))
    let capture = CompletionCapture()
    var raised: Error?
    do {
      // `sendData` rather than `send(_:)`: the async entry point hops onto the client's own queue,
      // putting the raise on a thread no caller can wrap. The client is expected to convert the raise
      // itself; this guard is only here so that a regression fails one test rather than aborting the
      // whole test process, which is what it does to `idb_companion`.
      try FBObjCExceptionGuard.run {
        client.sendData(Data([0x01, 0x02])) {
          capture.wasCalled = true
          capture.error = $0
        }
      }
    } catch {
      raised = error
    }

    #expect(raised == nil)
    #expect(capture.wasCalled)
    let completionError = try #require(capture.error) as NSError
    #expect(completionError.domain == FBObjCExceptionGuardErrorDomain)
    #expect(completionError.localizedDescription == RaisingSendLegacyHIDClientStub.reason)
  }
}
