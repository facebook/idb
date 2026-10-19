/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
@testable import FBSimulatorAX
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
