/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorAX
import FBSimulatorBridgeProtocol
@testable import FBSimulatorControl
import Foundation
import XCTest

// The tests spell trees as the guest writes them on the wire, keyed by `AXWire.Node`. These decode such a tree the
// way the host decodes a read, so a fixture the decoder cannot read fails the test that uses it.

extension BridgeAXNode {
  init(wire: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
    do {
      self = try JSONDecoder().decode(BridgeAXNode.self, from: JSONSerialization.data(withJSONObject: wire))
    } catch {
      XCTFail("not a node the guest could have sent: \(error)", file: file, line: line)
      self.init()
    }
  }
}

extension AXTreeWalk {
  static func describeAllElements(
    fromTree tree: [String: Any], keys: Set<AXKeys>, nestedFormat: Bool, pid: pid_t, file: StaticString = #filePath, line: UInt = #line
  ) -> [AccessibilityDocumentElement] {
    describeAllElements(fromTree: BridgeAXNode(wire: tree, file: file, line: line), keys: keys, nestedFormat: nestedFormat, pid: pid)
  }

  static func snapshot(fromTree tree: [String: Any], pid: pid_t, file: StaticString = #filePath, line: UInt = #line) -> AXElementSnapshot {
    snapshot(fromTree: BridgeAXNode(wire: tree, file: file, line: line), pid: pid)
  }

  static func screenInfo(fromTree tree: [String: Any], file: StaticString = #filePath, line: UInt = #line) -> AccessibilityScreenInfo? {
    screenInfo(fromTree: BridgeAXNode(wire: tree, file: file, line: line))
  }
}

extension AXBridgeSnapshotDecoder {
  static func snapshot(fromTree tree: [String: Any], pid: pid_t, file: StaticString = #filePath, line: UInt = #line) -> AXElementSnapshot {
    snapshot(fromTree: BridgeAXNode(wire: tree, file: file, line: line), pid: pid)
  }

  static func snapshot(
    fromNode node: [String: Any], pid: pid_t, children: [AXElementSnapshot] = [], file: StaticString = #filePath, line: UInt = #line
  ) -> AXElementSnapshot {
    snapshot(fromNode: BridgeAXNode(wire: node, file: file, line: line), pid: pid, children: children)
  }
}

extension AXTreeRead {
  init(tree: [String: Any], pid: pid_t, truncated: Bool, modal: AccessibilityModalInfo?, file: StaticString = #filePath, line: UInt = #line) {
    self.init(tree: BridgeAXNode(wire: tree, file: file, line: line), pid: pid, truncated: truncated, modal: modal)
  }
}

// The read tests spell a guest's answer as the envelope it writes. These decode it as the transport does, for the
// request it would answer, so an envelope the guest could not have sent fails as the transport fails it.

private let anyReadOptions = BridgeAXReadOptions(
  maxDepth: 1, maxNodes: 1, attributes: nil, explainUnreachable: false, traversal: .viewHierarchy, automationMode: nil, clientType: .noClient)

extension AXTreeRead {
  init(wholeTreeResponse data: Data, pid: pid_t) throws {
    try self.init(wholeTreeResponse: AXBridgeReply(answer: data, for: .read(pid: pid, options: anyReadOptions)).answer, pid: pid)
  }

  init(frontmostResponse data: Data, method: AXBridgeFrontmostMethod) throws {
    try self.init(
      frontmostResponse: AXBridgeReply(answer: data, for: .readFrontmost(x: 0, y: 0, method: method, options: anyReadOptions)).answer,
      method: method)
  }

  init?(hitTestResponse data: Data) throws {
    try self.init(hitTestResponse: AXBridgeReply(answer: data, for: .hitTest(x: 0, y: 0, attributes: nil, clientType: .noClient)).answer)
  }

  static func writeLanded(fromResponse data: Data) throws -> Bool {
    try writeLanded(fromResponse: AXBridgeReply(answer: data, for: anyWrite).answer)
  }

  static func writeSentNothing(fromResponse data: Data) -> Bool {
    guard let answer = try? AXBridgeReply(answer: data, for: anyWrite).answer else { return false }
    return writeSentNothing(fromResponse: answer)
  }

  private static var anyWrite: AXBridgeRequest {
    .write(AXBridgeWriteRequest(kind: .perform(.press), x: 0, y: 0, pid: nil, assertion: nil))
  }
}

extension QuiescenceEvent {
  init(axBridgeFrame data: Data, pid: pid_t?) throws {
    try self.init(
      axBridgeFrame: AXBridgeReply(answer: data, for: .quiescence(pid: pid, busyThresholdMs: nil, quietWindowMs: nil)).answer, pid: pid)
  }
}

// The guest's answers, as a frame carries them, for the doubles to return. Trees are spelled as the guest writes them
// on the wire; everything around them is the typed answer.

func answerData(_ answer: BridgeAXAnswer) throws -> Data {
  try JSONEncoder().encode(answer)
}

func treeAnswer(
  _ tree: [String: Any], pid: Int32, truncated: Bool = false, automation: BridgeAXAutomationState? = nil, method: BridgeAXFrontmostMethod? = nil,
  modal: BridgeAXModal? = nil
) throws -> Data {
  try answerData(
    .tree(BridgeAXTreeResponse(tree: BridgeAXNode(wire: tree), pid: pid, truncated: truncated, automation: automation, method: method, modal: modal)))
}

func hitAnswer(_ tree: [String: Any], pid: Int32) throws -> Data {
  try answerData(.hitTest(.element(BridgeAXNode(wire: tree), pid: pid)))
}

func emptyHitAnswer() throws -> Data {
  try answerData(.hitTest(.empty))
}

func writtenAnswer(pid: Int32) throws -> Data {
  try answerData(.write(.written(pid: pid)))
}

func emptyWriteAnswer() throws -> Data {
  try answerData(.write(.empty))
}

func failureAnswer(_ message: String?, kind: String? = nil, pid: Int32? = nil) throws -> Data {
  try answerData(.failure(BridgeAXFailure(message: message, kind: kind.flatMap(BridgeAXWire.ErrorKind.init(rawValue:)), pid: pid)))
}
