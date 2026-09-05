/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import ObjectiveC
import Testing

/// Stands in for the informal protocols production call sites declare for classes they never name
/// as a type. The initializer is in the `init` family, as the real ones are.
@objc private protocol StubClientMessaging {
  @objc(initWithName:error:)
  func initWithName(_ name: String, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> AnyObject?
}

private final class SucceedingStub: NSObject, StubClientMessaging {
  private(set) var receivedName: String?

  func initWithName(_ name: String, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> AnyObject? {
    receivedName = name
    return self
  }
}

private final class NilReturningStub: NSObject, StubClientMessaging {
  func initWithName(_ name: String, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> AnyObject? {
    nil
  }
}

private final class RaisingStub: NSObject, StubClientMessaging {
  static let reason = "the stub initializer raised"

  func initWithName(_ name: String, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> AnyObject? {
    NSException(name: .internalInconsistencyException, reason: Self.reason, userInfo: ["stub": name]).raise()
    return nil
  }
}

@Suite("Runtime-resolved Objective-C classes")
struct FBObjCRuntimeClassTests {

  // MARK: - Lookup

  @Test("A loaded class resolves under the name it was asked for")
  func lookUpLoadedClass() throws {
    let runtimeClass = try #require(FBObjCRuntimeClass(name: "NSObject"))
    #expect(runtimeClass.name == "NSObject")
    #expect(ObjectIdentifier(runtimeClass.cls) == ObjectIdentifier(NSObject.self))
  }

  @Test("A class that is not in the process does not resolve")
  func lookUpAbsentClass() {
    #expect(FBObjCRuntimeClass(name: "FBObjCRuntimeClassTestsNoSuchClass") == nil)
  }

  // MARK: - Instantiation

  @Test("A successful initializer hands back the instance it was sent to")
  func instantiateSucceeds() throws {
    let runtimeClass = FBObjCRuntimeClass(SucceedingStub.self)
    let instance = try runtimeClass.instantiate(as: StubClientMessaging.self) {
      $0.initWithName("indigo", error: nil)
    }
    #expect(try #require(instance as? SucceedingStub).receivedName == "indigo")
  }

  @Test("An initializer that returns nil surfaces as a failure, not as a nil instance")
  func instantiateReturningNil() throws {
    let runtimeClass = FBObjCRuntimeClass(NilReturningStub.self)
    let error = try #require(throws: FBObjCRuntimeClassError.self) {
      _ = try runtimeClass.instantiate(as: StubClientMessaging.self) {
        $0.initWithName("indigo", error: nil)
      }
    }
    guard case let .initializerReturnedNil(className) = error else {
      Issue.record("Expected initializerReturnedNil, got \(error)")
      return
    }
    #expect(className == NSStringFromClass(NilReturningStub.self))
  }

  // An unguarded raise would unwind into libc++abi and abort the test process; reaching the
  // assertions is itself the check.
  @Test("An initializer that raises is converted into a Swift error")
  func instantiateRaising() throws {
    let runtimeClass = FBObjCRuntimeClass(RaisingStub.self)
    let error = try #require(throws: FBObjCRuntimeClassError.self) {
      _ = try runtimeClass.instantiate(as: StubClientMessaging.self) {
        $0.initWithName("indigo", error: nil)
      }
    }
    guard case let .initializerRaised(className, underlying) = error else {
      Issue.record("Expected initializerRaised, got \(error)")
      return
    }
    #expect(className == NSStringFromClass(RaisingStub.self))

    let underlyingError = underlying as NSError
    #expect(underlyingError.domain == FBObjCExceptionGuardErrorDomain)
    #expect(underlyingError.localizedDescription == RaisingStub.reason)
    #expect(
      underlyingError.userInfo[FBObjCExceptionGuardExceptionNameKey] as? String
        == NSExceptionName.internalInconsistencyException.rawValue)
  }
}
