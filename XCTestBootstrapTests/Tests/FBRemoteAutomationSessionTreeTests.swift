/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest
@testable import XCTestBootstrap

/// A fake `RemoteInvoking` whose `fetchAttributes` returns per-element attributes keyed by a string
/// element handle, so the recursive tree walk can be exercised without a live DTX connection.
private actor FakeTreeInvoker: RemoteInvoking {

  private let labelAttribute: String
  private let childrenAttribute: String
  private let nodes: [String: (label: String, children: [String])]

  init(labelAttribute: String, childrenAttribute: String, nodes: [String: (label: String, children: [String])]) {
    self.labelAttribute = labelAttribute
    self.childrenAttribute = childrenAttribute
    self.nodes = nodes
  }

  func beginSession(clientProtocolVersion: Int, deadline: TimeInterval) async throws {}
  func exchangeCapabilities(deadline: TimeInterval) async throws -> sending Any? { NSDictionary() }
  func loadAccessibility(timeout: TimeInterval, deadline: TimeInterval) async throws {}
  func synthesizeEvent(_ record: sending Any, implicitConfirmationInterval: TimeInterval, deadline: TimeInterval) async throws {}
  func requestElement(atPoint point: sending Any, deadline: TimeInterval) async throws -> sending Any? { "root" as NSString }

  func fetchAttributes(_ attributes: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws -> sending Any? {
    let identifier = (element as? String) ?? ""
    guard let node = nodes[identifier] else { return NSDictionary() }
    var dict: [String: Any] = [labelAttribute: node.label]
    dict[childrenAttribute] = node.children as [Any]
    return dict as NSDictionary
  }

  func setAttribute(_ attribute: sending Any, value: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws {}
}

/// A fake whose hit-test (`requestElement(atPoint:)`) throws, so a pid-anchored read that must never
/// probe a screen point can be verified: if it hit-tested, the throw would surface.
private actor NoHitTestInvoker: RemoteInvoking {
  func beginSession(clientProtocolVersion: Int, deadline: TimeInterval) async throws {}
  func exchangeCapabilities(deadline: TimeInterval) async throws -> sending Any? { NSDictionary() }
  func loadAccessibility(timeout: TimeInterval, deadline: TimeInterval) async throws {}
  func synthesizeEvent(_ record: sending Any, implicitConfirmationInterval: TimeInterval, deadline: TimeInterval) async throws {}
  func requestElement(atPoint point: sending Any, deadline: TimeInterval) async throws -> sending Any? {
    throw NSError(domain: "NoHitTestInvoker", code: 1)
  }
  func fetchAttributes(_ attributes: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws -> sending Any? { NSDictionary() }
  func setAttribute(_ attribute: sending Any, value: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws {}
}

final class FBRemoteAutomationSessionTreeTests: XCTestCase {

  private static let label = "label"
  private static let children = "children"

  private func makeSession() -> FBRemoteAutomationSession {
    let invoker = FakeTreeInvoker(
      labelAttribute: Self.label,
      childrenAttribute: Self.children,
      nodes: [
        "root": ("root", ["c1", "c2"]),
        "c1": ("c1", ["g1"]),
        "c2": ("c2", []),
        "g1": ("g1", []),
      ]
    )
    return FBRemoteAutomationSession(invoker: invoker, processIdentifier: 0)
  }

  func testFetchAttributeTreeBuildsNestedTree() async throws {
    let session = makeSession()
    let result = try await session.fetchAttributeTree(
      from: "root" as NSString, attributes: [Self.label, Self.children], childrenAttribute: Self.children,
      depth: 0, maxDepth: 10, budget: 100
    )
    let node = result.node
    XCTAssertEqual(node[Self.label] as? String, "root")

    let children = try XCTUnwrap(node[Self.children] as? [[String: Any]])
    XCTAssertEqual(children.count, 2)
    XCTAssertEqual(children[0][Self.label] as? String, "c1")
    XCTAssertEqual(children[1][Self.label] as? String, "c2")

    let grandchildren = try XCTUnwrap(children[0][Self.children] as? [[String: Any]])
    XCTAssertEqual(grandchildren.count, 1)
    XCTAssertEqual(grandchildren[0][Self.label] as? String, "g1")

    XCTAssertTrue((children[1][Self.children] as? [[String: Any]])?.isEmpty ?? false)
    XCTAssertFalse(result.truncated, "A tree that fits within the depth and node bounds is not truncated.")
  }

  func testFetchAttributeTreeRespectsMaxDepth() async throws {
    let session = makeSession()
    let result = try await session.fetchAttributeTree(
      from: "root" as NSString, attributes: [Self.label, Self.children], childrenAttribute: Self.children,
      depth: 0, maxDepth: 1, budget: 100
    )
    let children = try XCTUnwrap(result.node[Self.children] as? [[String: Any]])
    XCTAssertEqual(children.count, 2)
    // maxDepth 1 stops before grandchildren.
    XCTAssertTrue((children[0][Self.children] as? [[String: Any]])?.isEmpty ?? false)
    XCTAssertTrue(result.truncated, "Reaching maxDepth with undescended children signals truncation.")
  }

  func testFetchAttributeTreeRespectsNodeBudget() async throws {
    let session = makeSession()
    // Budget of 2 admits the root and a single child before the walk stops.
    let result = try await session.fetchAttributeTree(
      from: "root" as NSString, attributes: [Self.label, Self.children], childrenAttribute: Self.children,
      depth: 0, maxDepth: 10, budget: 2
    )
    let children = try XCTUnwrap(result.node[Self.children] as? [[String: Any]])
    XCTAssertEqual(children.count, 1)
    XCTAssertTrue(result.truncated, "Exhausting the node budget before the walk finishes signals truncation.")
  }

  func testApplicationElementTreeForNonPositivePidYieldsEmptyTree() async throws {
    // A non-positive pid short-circuits to an empty tree before anchoring — no invoker call at all.
    let session = FBRemoteAutomationSession(invoker: NoHitTestInvoker(), processIdentifier: 0)
    let tree = try await session.applicationElementTree(
      forPid: 0, attributes: [Self.label], childrenAttribute: Self.children, maxDepth: 10, maxNodes: 100
    )
    XCTAssertNil(tree.root, "A non-positive pid yields an empty tree.")
    XCTAssertEqual(tree.processIdentifier, 0)
  }

  func testApplicationElementTreeForPositivePidDoesNotHitTest() async throws {
    // The pid-anchored read must anchor via `elementWithProcessIdentifier:` and never probe a screen
    // point. `NoHitTestInvoker` throws from `requestElement(atPoint:)`, so a reintroduced hit-test
    // would surface as a thrown error here — completing without throwing proves the probe is skipped.
    // (A non-positive pid, as in the test above, short-circuits before any invoker call, so it cannot
    // exercise this invariant; a positive pid drives the real anchor-then-walk path.)
    let session = FBRemoteAutomationSession(invoker: NoHitTestInvoker(), processIdentifier: 0)
    let tree = try await session.applicationElementTree(
      forPid: 4321, attributes: [Self.label], childrenAttribute: Self.children, maxDepth: 10, maxNodes: 100
    )
    XCTAssertEqual(tree.processIdentifier, 4321, "A positive pid anchors the tree at that pid, not via a hit-test.")
    XCTAssertNotNil(tree.root, "The root is read via elementWithProcessIdentifier:, not a point probe.")
  }
}
