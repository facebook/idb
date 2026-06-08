/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import AccessibilityPlatformTranslation
import AppKit
import FBControlCore
import Foundation

/// An opaque accessibility element with a managed token lifecycle.
///
/// The element's translation token remains registered as long as the element is
/// open, allowing serialization (attribute reads go through XPC callbacks routed
/// by token). Actions (tap, scroll) are direct calls on the element and do not
/// require the token. Call `close()` when done to deregister the token; after
/// close, serialization fails.
///
/// A pure-Swift class in FBSimulatorControl (FBControlCore never consumed it —
/// only the simulator-side facade does, which is now Swift too).
public final class FBAccessibilityElement {

  private let element: AXPMacPlatformElement
  private let request: FBAXTranslationRequest
  private let dispatcher: FBAXTranslationDispatcher
  private weak var simulator: FBSimulator?
  private var closed: Bool = false

  public init(element: AXPMacPlatformElement, request: FBAXTranslationRequest, dispatcher: FBAXTranslationDispatcher, simulator: FBSimulator) {
    self.element = element
    self.request = request
    self.dispatcher = dispatcher
    self.simulator = simulator
  }

  deinit {
    close()
  }

  // MARK: - Lifecycle

  /// Close the element, deregistering the token. Called automatically on dealloc
  /// as a safety net. After close, serialization fails.
  public func close() {
    if !closed {
      closed = true
      dispatcher.popRequest(request)
    }
  }

  // MARK: - Serialization

  /// Serialize the element to a full response (preserves profiling/coverage data).
  public func serialize(with options: FBAccessibilityRequestOptions) throws -> FBAccessibilityElementsResponse {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "serialize")
    }
    if options.enableProfiling && request.collector == nil {
      request.collector = FBAccessibilityProfilingCollector()
    }
    return try request.run(element, options: options)
  }

  /// Read the string value of a searchable accessibility key from this element.
  public func stringValue(forSearchableKey key: FBAXSearchableKey) throws -> String {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "read from")
    }
    guard let value = Self.stringValue(forKey: key, from: element) else {
      throw FBAccessibilityError.noStringValue(key: key.rawValue)
    }
    return value
  }

  // MARK: - Actions

  /// Perform an unconditional accessibility tap (AXPress) without any label verification.
  public func tap() throws {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "tap")
    }
    let actionNames = element.accessibilityActionNames() ?? []
    guard actionNames.contains("AXPress") else {
      throw FBAccessibilityError.pressUnsupported(supportedActions: FBCollectionInformation.oneLineDescription(from: actionNames))
    }
    guard element.accessibilityPerformPress() else {
      throw FBAccessibilityError.pressFailed
    }
  }

  /// Perform an accessibility scroll on the element.
  public func scroll(with direction: FBAccessibilityScrollDirection) throws {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "scroll")
    }
    switch direction {
    case .down:
      element.performScrollDownByPageAction()
    case .up:
      element.performScrollUpByPageAction()
    case .left:
      element.performScrollLeftByPageAction()
    case .right:
      element.performScrollRightByPageAction()
    case .visible:
      element.performScrollToVisible()
    }
  }

  /// Set the accessibility value of the element (e.g., text field content, slider position).
  @objc(setValue:error:)
  public func setValue(_ value: Any) throws {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "set value on")
    }
    element.setAccessibilityValue(value)
  }

  // MARK: - Descendant search (ownership-transferring)

  /// Searches the accessibility tree rooted at this element for a descendant
  /// matching the given value/key. If found, ownership of the request token is
  /// transferred to a new handle wrapping the found element, and the receiver is
  /// closed without popping. If not found, the receiver is closed and an error
  /// is thrown.
  public func findElement(withValue value: String, forKey key: FBAXSearchableKey, depth: UInt) throws -> FBAccessibilityElement {
    guard let found = Self.findElement(withValue: value, forKey: key, in: element, token: request.token, remainingDepth: depth) else {
      close()
      throw FBAccessibilityError.elementNotFound(key: key.rawValue, value: value, depth: depth)
    }
    assert(!closed, "Cannot transfer ownership from a closed element")
    guard let simulator else {
      throw FBAccessibilityError.simulatorDeallocated
    }
    let newHandle = FBAccessibilityElement(element: found, request: request, dispatcher: dispatcher, simulator: simulator)
    closed = true
    return newHandle
  }

  // MARK: - Private helpers

  private static func stringValue(forKey key: FBAXSearchableKey, from element: AXPMacPlatformElement) -> String? {
    switch key {
    case .label:
      return element.accessibilityLabel()
    case .uniqueID:
      return element.accessibilityIdentifier()
    case .value:
      return element.accessibilityValue() as? String
    case .title:
      return element.accessibilityTitle()
    case .role:
      return element.accessibilityRole()?.rawValue
    case .roleDescription:
      return element.accessibilityRoleDescription()
    case .subrole:
      return element.accessibilitySubrole()?.rawValue
    case .help:
      return element.accessibilityHelp()
    case .placeholder:
      return element.accessibilityPlaceholderValue()
    }
  }

  private static func children(of element: AXPMacPlatformElement) -> [AXPMacPlatformElement] {
    (element.accessibilityChildren() ?? []).map { unsafeBitCast($0 as AnyObject, to: AXPMacPlatformElement.self) }
  }

  private static func findElement(withValue value: String, forKey key: FBAXSearchableKey, in element: AXPMacPlatformElement, token: String, remainingDepth: UInt) -> AXPMacPlatformElement? {
    element.translation?.bridgeDelegateToken = token
    if let propertyValue = stringValue(forKey: key, from: element), propertyValue.contains(value) {
      return element
    }
    if remainingDepth == 0 {
      return nil
    }
    for child in children(of: element) {
      child.translation?.bridgeDelegateToken = token
      if let found = findElement(withValue: value, forKey: key, in: child, token: token, remainingDepth: remainingDepth - 1) {
        return found
      }
    }
    return nil
  }
}
