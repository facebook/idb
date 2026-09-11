/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import FBControlCore
import Foundation

/// Selects how an in-guest frontmost read resolves the foreground application.
public enum FBAXBridgeFrontmostMethod: String, Sendable, CaseIterable {
  case centerPoint = "center-point"
  case windowServer = "window-server"
  case runningBoard = "runningboard"
}

struct AXBridgeWriteAssertion: Sendable, Equatable {
  let key: AXWire.Node
  let value: String
}

struct AXBridgeWriteRequest: Sendable, Equatable {
  enum Kind: Sendable, Equatable {
    case perform(AXWire.Action)
    case setValue(String)
  }

  let kind: Kind
  let x: Double
  let y: Double
  let pid: pid_t?
  let assertion: AXBridgeWriteAssertion?

  var verb: AXWire.Verb {
    switch kind {
    case .perform: .perform
    case .setValue: .setValue
    }
  }

  var arguments: [String] {
    var arguments = ["accessibility", verb.rawValue]
    arguments += AXWire.Request.x.argument("\(x)")
    arguments += AXWire.Request.y.argument("\(y)")
    if let pid {
      arguments += AXWire.Request.pid.argument("\(pid)")
    }
    switch kind {
    case let .perform(action):
      arguments += AXWire.Request.action.argument(action.rawValue)
    case let .setValue(value):
      arguments += AXWire.Request.value.argument(value)
    }
    if let assertion {
      arguments += AXWire.Request.assertKey.argument(assertion.key.rawValue)
      arguments += AXWire.Request.assertValue.argument(assertion.value)
    }
    return arguments
  }

  var payload: [String: Any] {
    var payload: [String: Any] = [
      AXWire.Request.verb.key: verb.rawValue,
      AXWire.Request.x.key: x,
      AXWire.Request.y.key: y,
    ]
    if let pid {
      payload[AXWire.Request.pid.key] = Int(pid)
    }
    switch kind {
    case let .perform(action):
      payload[AXWire.Request.action.key] = action.rawValue
    case let .setValue(value):
      payload[AXWire.Request.value.key] = value
    }
    if let assertion {
      payload[AXWire.Request.assertKey.key] = assertion.key.rawValue
      payload[AXWire.Request.assertValue.key] = assertion.value
    }
    return payload
  }
}

struct AXBridgeReadRequest: Sendable, Equatable {
  let maxDepth: Int
  let maxNodes: Int
  let attributes: [String]?
  let explainUnreachable: Bool
  let traversal: AXTraversal
  let automationMode: Bool?

  func appendingArguments(to arguments: [String]) -> [String] {
    var arguments = arguments
    arguments += AXWire.Request.maxDepth.argument("\(maxDepth)")
    arguments += AXWire.Request.maxNodes.argument("\(maxNodes)")
    if let attributes, !attributes.isEmpty {
      arguments += AXWire.Request.attributes.argument(attributes.joined(separator: ","))
    }
    if explainUnreachable {
      arguments += AXWire.Request.explainUnreachable.argument("1")
    }
    switch traversal {
    case .semantic:
      arguments += AXWire.Request.translatorVocabulary.argument("1")
    case .singleFetch:
      arguments += AXWire.Request.snapshotTree.argument("1")
    case .viewHierarchy:
      break
    }
    if let automationMode {
      arguments += AXWire.Request.automationMode.argument(automationMode ? "1" : "0")
    }
    return arguments
  }

  func appendingPayload(to payload: [String: Any]) -> [String: Any] {
    var payload = payload
    payload[AXWire.Request.maxDepth.key] = maxDepth
    payload[AXWire.Request.maxNodes.key] = maxNodes
    if let attributes, !attributes.isEmpty {
      payload[AXWire.Request.attributes.key] = attributes
    }
    if explainUnreachable {
      payload[AXWire.Request.explainUnreachable.key] = true
    }
    if traversal == .semantic {
      payload[AXWire.Request.translatorVocabulary.key] = true
    }
    if traversal == .singleFetch {
      payload[AXWire.Request.snapshotTree.key] = true
    }
    if let automationMode {
      payload[AXWire.Request.automationMode.key] = automationMode
    }
    return payload
  }
}

enum AXBridgeRequest: Sendable {
  case read(pid: pid_t, options: AXBridgeReadRequest)
  case readFrontmost(x: Double, y: Double, method: FBAXBridgeFrontmostMethod, options: AXBridgeReadRequest)
  case hitTest(x: Double, y: Double, attributes: [String]?)
  case write(AXBridgeWriteRequest)
  case ping

  var mayRetry: Bool {
    switch self {
    case .write:
      false
    case .read, .readFrontmost, .hitTest, .ping:
      true
    }
  }

  var arguments: [String] {
    switch self {
    case let .read(pid, options):
      return options.appendingArguments(
        to: ["accessibility", AXWire.Verb.describe.rawValue]
          + AXWire.Request.pid.argument("\(pid)"))
    case let .readFrontmost(x, y, method, options):
      return options.appendingArguments(
        to: ["accessibility", AXWire.Verb.describe.rawValue]
          + AXWire.Request.x.argument("\(x)")
          + AXWire.Request.y.argument("\(y)")
          + AXWire.Request.method.argument(method.rawValue))
    case let .hitTest(x, y, attributes):
      var arguments =
        ["accessibility", AXWire.Verb.hitTest.rawValue]
        + AXWire.Request.x.argument("\(x)")
        + AXWire.Request.y.argument("\(y)")
      if let attributes, !attributes.isEmpty {
        arguments += AXWire.Request.attributes.argument(attributes.joined(separator: ","))
      }
      return arguments
    case let .write(request):
      return request.arguments
    case .ping:
      return ["accessibility", "ping"]
    }
  }

  var payload: [String: Any] {
    switch self {
    case let .read(pid, options):
      return options.appendingPayload(to: [
        AXWire.Request.verb.key: AXWire.Verb.describe.rawValue,
        AXWire.Request.pid.key: Int(pid),
      ])
    case let .readFrontmost(x, y, method, options):
      return options.appendingPayload(to: [
        AXWire.Request.verb.key: AXWire.Verb.describe.rawValue,
        AXWire.Request.x.key: x,
        AXWire.Request.y.key: y,
        AXWire.Request.method.key: method.rawValue,
      ])
    case let .hitTest(x, y, attributes):
      var payload: [String: Any] = [
        AXWire.Request.verb.key: AXWire.Verb.hitTest.rawValue,
        AXWire.Request.x.key: x,
        AXWire.Request.y.key: y,
      ]
      if let attributes, !attributes.isEmpty {
        payload[AXWire.Request.attributes.key] = attributes
      }
      return payload
    case let .write(request):
      return request.payload
    case .ping:
      return [AXWire.Request.verb.key: "ping"]
    }
  }
}
