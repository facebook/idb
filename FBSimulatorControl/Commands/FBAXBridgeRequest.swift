/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// Selects how an in-guest frontmost read resolves the foreground application.
public enum FBAXBridgeFrontmostMethod: String, Sendable, CaseIterable {
  case centerPoint = "center-point"
  case windowServer = "window-server"
  case runningBoard = "runningboard"
}

struct FBAXBridgeWriteAssertion: Sendable, Equatable {
  let key: FBAXWire.Node
  let value: String
}

struct FBAXBridgeWriteRequest: Sendable, Equatable {
  enum Kind: Sendable, Equatable {
    case perform(FBAXWire.Action)
    case setValue(String)
  }

  let kind: Kind
  let x: Double
  let y: Double
  let pid: pid_t?
  let assertion: FBAXBridgeWriteAssertion?

  var verb: FBAXWire.Verb {
    switch kind {
    case .perform: .perform
    case .setValue: .setValue
    }
  }

  var arguments: [String] {
    var arguments = ["accessibility", verb.rawValue]
    arguments += FBAXWire.Request.x.argument("\(x)")
    arguments += FBAXWire.Request.y.argument("\(y)")
    if let pid {
      arguments += FBAXWire.Request.pid.argument("\(pid)")
    }
    switch kind {
    case let .perform(action):
      arguments += FBAXWire.Request.action.argument(action.rawValue)
    case let .setValue(value):
      arguments += FBAXWire.Request.value.argument(value)
    }
    if let assertion {
      arguments += FBAXWire.Request.assertKey.argument(assertion.key.rawValue)
      arguments += FBAXWire.Request.assertValue.argument(assertion.value)
    }
    return arguments
  }

  var payload: [String: Any] {
    var payload: [String: Any] = [
      FBAXWire.Request.verb.key: verb.rawValue,
      FBAXWire.Request.x.key: x,
      FBAXWire.Request.y.key: y,
    ]
    if let pid {
      payload[FBAXWire.Request.pid.key] = Int(pid)
    }
    switch kind {
    case let .perform(action):
      payload[FBAXWire.Request.action.key] = action.rawValue
    case let .setValue(value):
      payload[FBAXWire.Request.value.key] = value
    }
    if let assertion {
      payload[FBAXWire.Request.assertKey.key] = assertion.key.rawValue
      payload[FBAXWire.Request.assertValue.key] = assertion.value
    }
    return payload
  }
}

struct FBAXBridgeReadRequest: Sendable, Equatable {
  let maxDepth: Int
  let maxNodes: Int
  let attributes: [String]?
  let explainUnreachable: Bool
  let traversal: FBAXTraversal
  let automationMode: Bool?

  func appendingArguments(to arguments: [String]) -> [String] {
    var arguments = arguments
    arguments += FBAXWire.Request.maxDepth.argument("\(maxDepth)")
    arguments += FBAXWire.Request.maxNodes.argument("\(maxNodes)")
    if let attributes, !attributes.isEmpty {
      arguments += FBAXWire.Request.attributes.argument(attributes.joined(separator: ","))
    }
    if explainUnreachable {
      arguments += FBAXWire.Request.explainUnreachable.argument("1")
    }
    switch traversal {
    case .semantic:
      arguments += FBAXWire.Request.translatorVocabulary.argument("1")
    case .singleFetch:
      arguments += FBAXWire.Request.snapshotTree.argument("1")
    case .viewHierarchy:
      break
    }
    if let automationMode {
      arguments += FBAXWire.Request.automationMode.argument(automationMode ? "1" : "0")
    }
    return arguments
  }

  func appendingPayload(to payload: [String: Any]) -> [String: Any] {
    var payload = payload
    payload[FBAXWire.Request.maxDepth.key] = maxDepth
    payload[FBAXWire.Request.maxNodes.key] = maxNodes
    if let attributes, !attributes.isEmpty {
      payload[FBAXWire.Request.attributes.key] = attributes
    }
    if explainUnreachable {
      payload[FBAXWire.Request.explainUnreachable.key] = true
    }
    if traversal == .semantic {
      payload[FBAXWire.Request.translatorVocabulary.key] = true
    }
    if traversal == .singleFetch {
      payload[FBAXWire.Request.snapshotTree.key] = true
    }
    if let automationMode {
      payload[FBAXWire.Request.automationMode.key] = automationMode
    }
    return payload
  }
}

enum FBAXBridgeRequest: Sendable {
  case read(pid: pid_t, options: FBAXBridgeReadRequest)
  case readFrontmost(x: Double, y: Double, method: FBAXBridgeFrontmostMethod, options: FBAXBridgeReadRequest)
  case hitTest(x: Double, y: Double, attributes: [String]?)
  case write(FBAXBridgeWriteRequest)
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
        to: ["accessibility", FBAXWire.Verb.describe.rawValue]
          + FBAXWire.Request.pid.argument("\(pid)"))
    case let .readFrontmost(x, y, method, options):
      return options.appendingArguments(
        to: ["accessibility", FBAXWire.Verb.describe.rawValue]
          + FBAXWire.Request.x.argument("\(x)")
          + FBAXWire.Request.y.argument("\(y)")
          + FBAXWire.Request.method.argument(method.rawValue))
    case let .hitTest(x, y, attributes):
      var arguments =
        ["accessibility", FBAXWire.Verb.hitTest.rawValue]
        + FBAXWire.Request.x.argument("\(x)")
        + FBAXWire.Request.y.argument("\(y)")
      if let attributes, !attributes.isEmpty {
        arguments += FBAXWire.Request.attributes.argument(attributes.joined(separator: ","))
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
        FBAXWire.Request.verb.key: FBAXWire.Verb.describe.rawValue,
        FBAXWire.Request.pid.key: Int(pid),
      ])
    case let .readFrontmost(x, y, method, options):
      return options.appendingPayload(to: [
        FBAXWire.Request.verb.key: FBAXWire.Verb.describe.rawValue,
        FBAXWire.Request.x.key: x,
        FBAXWire.Request.y.key: y,
        FBAXWire.Request.method.key: method.rawValue,
      ])
    case let .hitTest(x, y, attributes):
      var payload: [String: Any] = [
        FBAXWire.Request.verb.key: FBAXWire.Verb.hitTest.rawValue,
        FBAXWire.Request.x.key: x,
        FBAXWire.Request.y.key: y,
      ]
      if let attributes, !attributes.isEmpty {
        payload[FBAXWire.Request.attributes.key] = attributes
      }
      return payload
    case let .write(request):
      return request.payload
    case .ping:
      return [FBAXWire.Request.verb.key: "ping"]
    }
  }
}
