/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public let FBControlCoreErrorDomain = "com.facebook.FBControlCore"

@objc
open class FBControlCoreError: NSObject {

  // MARK: Properties

  private var domain: String
  private var describedAs: String?
  private var cause: NSError?
  private var additionalInfo: [String: Any]
  private var describeRecursively: Bool
  private var errorCode: Int

  // MARK: Initializers

  public required override init() {
    domain = FBControlCoreErrorDomain
    errorCode = 0
    additionalInfo = [:]
    describeRecursively = true
    super.init()
  }

  // MARK: Public Methods

  @objc open class func describe(_ description: String) -> Self {
    let instance = self.init()
    instance.describedAs = description
    return instance
  }

  @objc @discardableResult
  open func describe(_ description: String) -> Self {
    describedAs = description
    return self
  }

  @objc open class func caused(by cause: Error?) -> Self {
    let instance = self.init()
    instance.cause = cause.map { $0 as NSError }
    return instance
  }

  @objc @discardableResult
  open func caused(by cause: Error?) -> Self {
    self.cause = cause.map { $0 as NSError }
    return self
  }

  @objc @discardableResult
  open func failBool(_ error: NSErrorPointer) -> Bool {
    error?.pointee = build()
    return false
  }

  @objc @discardableResult
  open func failInt(_ error: NSErrorPointer) -> Int32 {
    error?.pointee = build()
    return 0
  }

  @objc @discardableResult
  open func failUInt(_ error: NSErrorPointer) -> UInt32 {
    error?.pointee = build()
    return 0
  }

  @objc @discardableResult
  open func failRect(_ error: NSErrorPointer) -> CGRect {
    error?.pointee = build()
    return CGRect.null
  }

  @objc @discardableResult
  open func fail(_ error: NSErrorPointer) -> Any? {
    error?.pointee = build()
    return nil
  }

  @objc open func failFuture() -> FBFuture<AnyObject> {
    return FBFuture<AnyObject>(error: build())
  }

  @objc open func failFutureContext() -> FBFutureContext<AnyObject> {
    return FBFutureContext<AnyObject>(error: build())
  }

  @objc @discardableResult
  open func failPointer(_ error: NSErrorPointer) -> UnsafeMutableRawPointer? {
    error?.pointee = build()
    return nil
  }

  @objc @discardableResult
  open func extraInfo(_ key: String, value: Any) -> Self {
    additionalInfo[key] = value
    return self
  }

  @objc @discardableResult
  open func recursiveDescription() -> Self {
    describeRecursively = true
    return self
  }

  @objc @discardableResult
  open func noRecursiveDescription() -> Self {
    describeRecursively = false
    return self
  }

  @objc @discardableResult
  open func inDomain(_ domain: String) -> Self {
    self.domain = domain
    return self
  }

  @objc @discardableResult
  open func code(_ code: Int) -> Self {
    errorCode = code
    return self
  }

  @objc open func build() -> NSError {
    // If there's just a cause, there's no error to build
    if let cause, describedAs == nil, additionalInfo.isEmpty {
      return cause
    }

    var userInfo: [String: Any] = [:]
    if let describedAs {
      userInfo[NSLocalizedDescriptionKey] = describedAs
    }
    if cause != nil {
      userInfo[NSUnderlyingErrorKey] = underlyingError()
    }
    for (key, value) in additionalInfo {
      userInfo[key] = value
    }

    return NSError(domain: domain, code: errorCode, userInfo: userInfo)
  }

  // MARK: NSObject

  open override var description: String {
    return build().description
  }

  // MARK: Private

  private func underlyingError() -> NSError? {
    guard let error = cause else {
      return cause
    }
    if !describeRecursively {
      return error
    }

    let description = NSMutableString(string: "\(error.localizedDescription)")
    var currentError: NSError = error
    while let underlying = currentError.userInfo[NSUnderlyingErrorKey] as? NSError {
      currentError = underlying
      description.append("\nCaused By: \(currentError.localizedDescription)")
    }

    var userInfo = error.userInfo
    userInfo[NSLocalizedDescriptionKey] = description as String
    return NSError(domain: error.domain, code: error.code, userInfo: userInfo)
  }
}

// MARK: - Constructors

extension FBControlCoreError {

  @objc public class func error(forDescription description: String) -> NSError {
    return Self.describe(description).build()
  }

  @objc public class func fail(withErrorMessage errorMessage: String, errorOut: NSErrorPointer) -> Any? {
    return Self.describe(errorMessage).fail(errorOut)
  }

  @objc(failWithError:errorOut:)
  public class func fail(with failureCause: NSError, errorOut: NSErrorPointer) -> Any? {
    return Self.caused(by: failureCause).fail(errorOut)
  }

  @objc(failWithError:description:errorOut:)
  public class func fail(with failureCause: NSError, description: String, errorOut: NSErrorPointer) -> Any? {
    return Self.caused(by: failureCause).describe(description).fail(errorOut)
  }

  @objc public class func failBool(withErrorMessage errorMessage: String, errorOut: NSErrorPointer) -> Bool {
    return Self.describe(errorMessage).failBool(errorOut)
  }

  @objc(failBoolWithError:errorOut:)
  @discardableResult
  public class func failBool(with failureCause: NSError, errorOut: NSErrorPointer) -> Bool {
    return Self.caused(by: failureCause).failBool(errorOut)
  }

  @objc(failBoolWithError:description:errorOut:)
  @discardableResult
  public class func failBool(with failureCause: NSError, description: String, errorOut: NSErrorPointer) -> Bool {
    return Self.caused(by: failureCause).describe(description).failBool(errorOut)
  }

  @objc(failFutureWithError:)
  public class func failFuture(with error: NSError) -> FBFuture<AnyObject> {
    return FBFuture<AnyObject>(error: error)
  }
}
