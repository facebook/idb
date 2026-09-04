/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore

struct FBAXWriteTarget: Equatable {
  let point: CGPoint
  let pid: pid_t?
  let assertion: FBAXBridgeWriteAssertion?
}

extension FBAXBridgeTreeReader {
  func writeTarget(
    for query: FBAccessibilityElementQuery,
    operation: String,
    callerAssertion: FBTapOptions.Assertion? = nil
  ) async throws -> FBAXWriteTarget {
    switch query {
    case let .point(point):
      if let callerAssertion {
        try await assertBeforeWriting(callerAssertion, atPoint: point)
      }
      return FBAXWriteTarget(point: point, pid: nil, assertion: nil)
    case let .marker(value, key, _, ignoresCase):
      // Writes resolve against the structural tree: a semantic traversal can omit the element a marker names.
      let read = try await readRawTree(
        for: query,
        attributes: nil,
        explainUnreachable: false,
        traversal: .viewHierarchy
      )
      await warnIfTruncated(read.truncated)
      let elements = FBAXTreeWalk.describeAllElements(
        fromTree: read.tree,
        keys: FBAXKeys.defaultSet.union([key.serializationKey]),
        nestedFormat: false,
        pid: read.pid
      )
      guard let match = FBAXTreeWalk.matchingElement(inElements: elements, markerValue: value, key: key, ignoresCase: ignoresCase) else {
        throw FBUIAutomationError.elementNotFound(backend: backend, key: key.rawValue, value: value)
      }
      try validate(callerAssertion, against: match)
      switch FBAXTreeWalk.resolveMarker(inElements: elements, markerValue: value, key: key, ignoresCase: ignoresCase) {
      case let .resolved(x, y):
        // Marker lookup is a substring match, but the guest's safety check is equality. Assert the
        // matched element's actual value rather than the substring the caller searched for.
        return FBAXWriteTarget(
          point: CGPoint(x: x, y: y),
          pid: read.pid,
          assertion: Self.derivedAssertion(from: match, key: key)
        )
      case .offScreen:
        throw FBUIAutomationError.elementNotOnScreen(backend: backend, key: key.rawValue, value: value)
      case .notFound:
        throw FBUIAutomationError.elementNotFound(backend: backend, key: key.rawValue, value: value)
      }
    case .frontmost, .application:
      throw FBUIAutomationError.pointOrMarkerRequired(backend: backend, operation: operation)
    }
  }

  func emptyWriteTargetError(for query: FBAccessibilityElementQuery, at point: CGPoint) -> FBUIAutomationError {
    guard case let .marker(value, key, _, _) = query else {
      return .noElementAtPoint(backend: backend, x: Double(point.x), y: Double(point.y))
    }
    return .elementMoved(backend: backend, key: key.rawValue, value: value)
  }

  private static func derivedAssertion(
    from match: FBAccessibilityDocumentElement,
    key: FBAXSearchableKey
  ) -> FBAXBridgeWriteAssertion? {
    guard let node = FBAXWire.Node(assertableSearchKey: key), let actual = match.searchableValue(for: key) else {
      return nil
    }
    return FBAXBridgeWriteAssertion(key: node, value: actual)
  }

  private func assertBeforeWriting(_ assertion: FBTapOptions.Assertion, atPoint point: CGPoint) async throws {
    let options = FBAccessibilityRequestOptions(keys: FBAXKeys.defaultSet.union([assertion.key.serializationKey]))
    guard let response = try await hitTest(at: point, options: options),
      let element = response.elements.elements.first
    else {
      throw FBUIAutomationError.noElementAtPoint(backend: backend, x: Double(point.x), y: Double(point.y))
    }
    try validate(assertion, against: element)
  }

  private func validate(
    _ assertion: FBTapOptions.Assertion?,
    against element: FBAccessibilityDocumentElement
  ) throws {
    guard let assertion else {
      return
    }
    let actual = element.searchableValue(for: assertion.key) ?? ""
    guard actual == assertion.value else {
      throw FBUIAutomationError.valueMismatch(
        backend: backend,
        key: assertion.key.rawValue,
        expected: assertion.value,
        actual: actual
      )
    }
  }
}
