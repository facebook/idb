/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

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

@Suite("Legacy Indigo HID client creation")
struct FBSimulatorIndigoHIDClientTests {

  @Test("An initializer that raises takes the process with it")
  func clientInitializerRaises() throws {
    let clientClass = FBObjCRuntimeClass(RaisingLegacyHIDClientStub.self)
    var thrown: Error?
    var raised: Error?
    do {
      // The guard sits in the test, not in the client — which is the bug being pinned. In
      // `idb_companion` there is no `@catch` anywhere on the stack between the gRPC `hid` handler
      // and this initializer, so the raise reaches `libc++abi` and aborts the whole process.
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

    // BUG: nothing is thrown, because the raise unwinds straight out of the client and is only
    // stopped by this test's own guard — flipped in the following commit.
    #expect(thrown == nil)
    let raisedError = try #require(raised) as NSError
    #expect(raisedError.domain == FBObjCExceptionGuardErrorDomain)
    #expect(raisedError.localizedDescription == RaisingLegacyHIDClientStub.reason)
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
}
