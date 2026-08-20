/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

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
final class FBAccessibilityElement {

  private let element: FBAXWritableElement
  private let request: FBAXTranslationRequest
  private let dispatcher: FBAXTranslationDispatcher
  private weak var simulator: FBSimulator?
  private var closed: Bool = false

  /// The frame of the root this element was found under, for an element reached by descending a tree.
  ///
  /// Such an element knows the bounds its own frame is relative to, but cannot report them: the
  /// serializer takes a read's screen bounds from the element it is handed, and for a descendant that
  /// is the descendant's frame. So the root's frame is captured at the descent and carried here. `nil`
  /// for an element read directly, which has no root to speak for.
  let rootBounds: CGRect?

  init(
    element: FBAXWritableElement,
    request: FBAXTranslationRequest,
    dispatcher: FBAXTranslationDispatcher,
    simulator: FBSimulator,
    rootBounds: CGRect? = nil
  ) {
    self.element = element
    self.request = request
    self.dispatcher = dispatcher
    self.simulator = simulator
    self.rootBounds = rootBounds
  }

  deinit {
    close()
  }

  // MARK: - Lifecycle

  /// Close the element, deregistering the token. Called automatically on dealloc
  /// as a safety net. After close, serialization fails.
  func close() {
    if !closed {
      closed = true
      dispatcher.popRequest(request)
    }
  }

  // MARK: - Serialization

  /// Serialize the element to a full response (preserves profiling/coverage data).
  func serialize(with options: FBAccessibilityRequestOptions) async throws -> FBAccessibilityElementsResponse {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "serialize")
    }
    if options.enableProfiling && request.collector == nil {
      request.collector = FBAccessibilityProfilingCollector()
    }
    // Wire the per-request logger from the option so the dispatcher's XPC
    // callbacks (which capture `request.logger`) actually emit request/response
    // logging during the serialization walk. Mirrors the `collector` wiring above.
    request.logger = options.enableLogging ? simulator?.logger : nil
    let request = self.request
    let element = self.element
    let namesTheTarget = self.namesTheTarget
    return try await dispatcher.performSerialized {
      try request.run(element, options: options, namesTheTarget: namesTheTarget)
    }
  }

  /// Whether this handle names the one element the caller asked for, rather than the tree its request
  /// resolved. True exactly for a marker match, which `findElement` reached by descending from the root
  /// — the same descent that captured `rootBounds`, which is why that is the signal.
  private var namesTheTarget: Bool {
    rootBounds != nil
  }

  /// Read the string value of a searchable accessibility key from this element.
  func stringValue(forSearchableKey key: FBAXSearchableKey) async throws -> String {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "read from")
    }
    let element = self.element
    guard let value = try await dispatcher.performSerialized({ Self.stringValue(forKey: key, from: element) }) else {
      throw FBAccessibilityError.noStringValue(key: key.rawValue)
    }
    return value
  }

  // MARK: - Actions

  /// Perform an unconditional accessibility tap (AXPress) without any label verification.
  func tap() async throws {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "tap")
    }
    let element = self.element
    try await dispatcher.performSerialized {
      let actionNames = element.axActionNames()
      guard actionNames.contains("AXPress") else {
        throw FBAccessibilityError.pressUnsupported(supportedActions: FBCollectionInformation.oneLineDescription(from: actionNames))
      }
      guard element.axPerformPress() else {
        throw FBAccessibilityError.pressFailed
      }
    }
  }

  /// Perform an accessibility scroll on the element.
  func scroll(with direction: FBAccessibilityScrollDirection) async throws {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "scroll")
    }
    let element = self.element
    try await dispatcher.performSerialized { element.axScroll(direction) }
  }

  /// Set the accessibility value of the element (e.g., text field content, slider position).
  func setValue(_ value: String) async throws {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "set value on")
    }
    let element = self.element
    try await dispatcher.performSerialized { element.axSetValue(value) }
  }

  // MARK: - Geometry

  /// The element's frame in screen points. The element must be open.
  func frame() async throws -> CGRect {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "read the frame of")
    }
    let element = self.element
    let token = request.token
    return try await dispatcher.performSerialized {
      element.axSetBridgeDelegateToken(token)
      return element.axFrame()
    }
  }

  /// The pid of the backing translation object (0 when absent). A zero-serialization identity read —
  /// used to anchor a remote-automation frontmost read on the app's pid instead of a screen hit-test.
  var processIdentifier: pid_t {
    element.axTranslationPid
  }

  // MARK: - Descendant search (ownership-transferring)

  /// Searches the accessibility tree rooted at this element for a descendant
  /// matching the given value/key. If found, ownership of the request token is
  /// transferred to a new handle wrapping the found element, and the receiver is
  /// closed without popping. If not found, the receiver is closed and an error
  /// is thrown.
  func findElement(withValue value: String, forKey key: FBAXSearchableKey, depth: UInt) async throws -> FBAccessibilityElement {
    // The legacy accessibility tree is composed entirely of `AXPMacPlatformElement`, so any matched
    // descendant is writable; the cast is total in practice. A (structurally impossible) read-only
    // match is reported as not-found rather than wrapped in a handle whose actions could not dispatch.
    //
    // The root's bounds are read in the same serialized hop, before handing ownership on: this element
    // is the root the match was found under, and once the new handle is serializing there is nothing
    // left that knows the bounds the match's frame is relative to.
    let element = self.element
    let token = request.token
    let match = try await dispatcher.performSerialized { () -> (found: FBAXWritableElement, rootBounds: CGRect)? in
      guard let found = Self.findElement(withValue: value, forKey: key, in: element, token: token, remainingDepth: depth) as? FBAXWritableElement else {
        return nil
      }
      element.axSetBridgeDelegateToken(token)
      return (found, element.axFrame())
    }
    guard let match else {
      close()
      throw FBAccessibilityError.elementNotFound(key: key.rawValue, value: value, depth: depth)
    }
    assert(!closed, "Cannot transfer ownership from a closed element")
    guard let simulator else {
      throw FBWeakTargetError.simulator
    }
    let newHandle = FBAccessibilityElement(
      element: match.found, request: request, dispatcher: dispatcher, simulator: simulator, rootBounds: match.rootBounds
    )
    closed = true
    return newHandle
  }

  // MARK: - Private helpers

  private static func stringValue(forKey key: FBAXSearchableKey, from element: FBAXPlatformElement) -> String? {
    switch key {
    case .label:
      return element.axLabel()
    case .uniqueID:
      return element.axIdentifier()
    case .value:
      return element.axValue() as? String
    case .title:
      return element.axTitle()
    case .role:
      return element.axRole()
    case .roleDescription:
      return element.axRoleDescription()
    case .subrole:
      return element.axSubrole()
    case .help:
      return element.axHelp()
    case .placeholder:
      return element.axPlaceholderValue()
    }
  }

  private static func findElement(withValue value: String, forKey key: FBAXSearchableKey, in element: FBAXPlatformElement, token: String, remainingDepth: UInt) -> FBAXPlatformElement? {
    element.axSetBridgeDelegateToken(token)
    if let propertyValue = stringValue(forKey: key, from: element), propertyValue.contains(value) {
      return element
    }
    if remainingDepth == 0 {
      return nil
    }
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      if let found = findElement(withValue: value, forKey: key, in: child, token: token, remainingDepth: remainingDepth - 1) {
        return found
      }
    }
    return nil
  }
}
