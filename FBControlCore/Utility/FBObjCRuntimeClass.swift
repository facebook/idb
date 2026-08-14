/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import ObjectiveC

/// The ways instantiating a runtime-resolved class can fail.
public enum FBObjCRuntimeClassError: Error, LocalizedError {
  /// The instance could not be allocated, so no initializer was ever sent.
  case allocationFailed(className: String)
  /// The designated initializer raised an `NSException` instead of returning.
  case initializerRaised(className: String, underlying: Error)
  /// The designated initializer returned nil.
  case initializerReturnedNil(className: String)

  public var errorDescription: String? {
    switch self {
    case let .allocationFailed(className):
      return "An instance of \(className) could not be allocated"
    case let .initializerRaised(className, underlying):
      return "The initializer of \(className) raised: \(underlying.localizedDescription)"
    case let .initializerReturnedNil(className):
      return "The initializer of \(className) returned nil"
    }
  }
}

/**
 A class obtained from the Objective-C runtime by name, rather than named as a type.

 Private framework classes move between framework binaries across OS and Xcode releases. Naming one
 as a type emits a link-time `_OBJC_CLASS_$_Name` reference pinned to whichever framework vended it
 at build time, and the process fails to launch once it moves. Looking the class up by name avoids
 the symbol, at the cost of hand-rolling what the compiler would otherwise do: allocate, send the
 designated initializer, and interpret the result.

 `instantiate` is where that hand-rolling is worth sharing. The initializer send crosses into code
 this process does not own, which is free to raise `NSException` — and a raise that unwinds through
 a Swift frame reaches `libc++abi` and aborts the process, because `do`/`catch` cannot see it. The
 send is therefore funnelled through `FBObjCExceptionGuard`, so a raise arrives as a thrown
 `FBObjCRuntimeClassError` that the caller can map onto its own failure modes.
 */
public struct FBObjCRuntimeClass {

  /// The name the class was resolved under.
  public let name: String
  /// The resolved class.
  public let cls: AnyClass

  /// Looks a class up in the Objective-C runtime, returning nil when no class of that name is
  /// registered. Loading whatever vends the class is the caller's responsibility — a lookup only
  /// sees classes belonging to images that are already in the process.
  public init?(name: String) {
    guard let cls = objc_lookUpClass(name) else {
      return nil
    }
    self.name = name
    self.cls = cls
  }

  /// Wraps a class that has already been resolved.
  public init(_ cls: AnyClass) {
    self.name = NSStringFromClass(cls)
    self.cls = cls
  }

  /**
   Allocates an instance and sends it its designated initializer.

   `Messaging` is an `@objc` protocol declaring the initializer's selector. The fresh allocation is
   `unsafeBitCast` to it, which is what lets `initialize` express the send in Swift without the
   class ever being named as a type. The cast is only defined when `Messaging` is laid out as an
   object pointer, which is what the `AnyObject` constraint holds callers to.

   - Parameter initialize: Sends the designated initializer to the allocation, returning whatever it
     returned. Must not escape the instance it is passed — until the initializer returns, the object
     is not fully formed.
   - Throws: `FBObjCRuntimeClassError.allocationFailed` if the instance could not be allocated,
     `FBObjCRuntimeClassError.initializerRaised` if the initializer raised an `NSException`,
     `FBObjCRuntimeClassError.initializerReturnedNil` if it returned nil.
   */
  public func instantiate<Messaging: AnyObject>(
    as _: Messaging.Type,
    _ initialize: (Messaging) -> AnyObject?
  ) throws -> AnyObject {
    // Unwrapped rather than bridged: `Optional.none as AnyObject` boxes into a non-nil `NSNull`, so a
    // failed allocation would go on to be messaged and be reported as a raising initializer.
    guard let instance = class_createInstance(cls, 0) else {
      throw FBObjCRuntimeClassError.allocationFailed(className: name)
    }
    let allocated = unsafeBitCast(instance as AnyObject, to: Messaging.self)
    let initialized: AnyObject?
    do {
      initialized = try FBObjCExceptionGuard.guarded { initialize(allocated) }
    } catch {
      // A method in the `init` family consumes its receiver, so a raise leaves the allocation owned
      // by an initializer that never returned. Nothing releases it and one object leaks — the
      // deliberate trade against running `dealloc` over ivars that were never set.
      throw FBObjCRuntimeClassError.initializerRaised(className: name, underlying: error)
    }
    guard let initialized else {
      throw FBObjCRuntimeClassError.initializerReturnedNil(className: name)
    }
    return initialized
  }
}
