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

/// Records whether a send started on another task has come back, and with what. Locked because the
/// send resolves on the client's queue while the test reads from its own thread.
private final class SendOutcome: @unchecked Sendable {
  private let lock = NSLock()
  private var state: (returned: Bool, error: Error?) = (false, nil)

  func record(_ error: Error?) {
    lock.lock()
    defer { lock.unlock() }
    state = (true, error)
  }

  var returned: Bool {
    lock.lock()
    defer { lock.unlock() }
    return state.returned
  }

  var error: Error? {
    lock.lock()
    defer { lock.unlock() }
    return state.error
  }
}

@Suite("Legacy Indigo HID client")
struct FBSimulatorIndigoHIDClientTests {

  @Test("An initializer that raises surfaces the raise as a client creation failure")
  func clientInitializerRaises() throws {
    let clientClass = FBObjCRuntimeClass(RaisingLegacyHIDClientStub.self)
    var thrown: Error?
    var raised: Error?
    do {
      // The client is expected to convert the raise itself. The guard only keeps a regression from
      // aborting the whole test process instead of failing this test.
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

  @Test("A send the client reports as failed throws to the caller")
  func sendReportsClientFailure() async throws {
    let client = try FBSimulatorIndigoHIDClient(
      device: NSObject(), clientClass: FBObjCRuntimeClass(FailingSendLegacyHIDClientStub.self))
    let error = try await #require(throws: (any Error).self) {
      try await client.send(Data([0x01, 0x02]))
    }
    #expect(error.localizedDescription == FailingSendLegacyHIDClientStub.reason)
  }

  @Test("A send whose client raises throws the raise to the caller")
  func sendRaises() async throws {
    let client = try FBSimulatorIndigoHIDClient(
      device: NSObject(), clientClass: FBObjCRuntimeClass(RaisingSendLegacyHIDClientStub.self))
    // The send runs on the client's own queue, so nothing here can wrap it: an unguarded raise
    // aborts the test process rather than failing this test.
    let error = try await #require(throws: (any Error).self) {
      try await client.send(Data([0x01, 0x02]))
    }
    #expect((error as NSError).domain == FBObjCExceptionGuardErrorDomain)
    #expect(error.localizedDescription == RaisingSendLegacyHIDClientStub.reason)
  }

  @Test("A send after the client is disconnected comes back to the caller")
  func sendAfterDisconnect() async throws {
    let client = try FBSimulatorIndigoHIDClient(
      device: NSObject(), clientClass: FBObjCRuntimeClass(FailingSendLegacyHIDClientStub.self))
    client.disconnect()

    let outcome = SendOutcome()
    Task {
      do {
        try await client.send(Data([0x01, 0x02]))
        outcome.record(nil)
      } catch {
        outcome.record(error)
      }
    }
    // Bounded sleep rather than an await: nothing here reaches the HID server, so a send that
    // returns at all returns at once, and one still outstanding after this hangs for good.
    try await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)

    #expect(outcome.returned)
    guard case .clientDisposed? = outcome.error as? FBSimulatorHIDError else {
      Issue.record("Expected clientDisposed, got \(String(describing: outcome.error))")
      return
    }
  }
}
