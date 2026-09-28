/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import FBControlCore
import Foundation
import SimulatorFrameworkBridgeProtocol

/// Selects how an in-guest frontmost read resolves the foreground application.
public enum AXBridgeFrontmostMethod: String, Sendable, CaseIterable {
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
  var displayID: UInt32?

  var verb: AXWire.Verb {
    switch kind {
    case .perform: .perform
    case .setValue: .setValue
    }
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
    if let displayID {
      payload[AXWire.Request.displayID.key] = displayID
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
  case read(pid: pid_t, options: AXBridgeReadRequest, displayID: UInt32? = nil)
  case readFrontmost(x: Double, y: Double, method: AXBridgeFrontmostMethod, options: AXBridgeReadRequest, displayID: UInt32? = nil)
  case hitTest(x: Double, y: Double, attributes: [String]?, displayID: UInt32? = nil)
  case write(AXBridgeWriteRequest)
  case deviceSettingRead(String)
  case deviceSettingWrite(String, enabled: Bool)
  /// Streamed: follows the frontmost application on `displayID` when `pid` is nil. A nil tunable takes the guest's default.
  case quiescence(pid: pid_t?, busyThresholdMs: Int?, quietWindowMs: Int?, displayID: UInt32? = nil)
  case displays

  var command: BridgeCommand {
    get throws { .accessibility(try payload.mapValues(BridgeJSONValue.init(foundationValue:))) }
  }

  var mayRetry: Bool { (try? command.mayRetry) ?? false }

  var arguments: [String] {
    get throws { try BridgeRequest(command: command).arguments }
  }

  var payload: [String: Any] {
    switch self {
    case let .read(pid, options, displayID):
      var payload: [String: Any] = [
        AXWire.Request.verb.key: AXWire.Verb.describe.rawValue,
        AXWire.Request.pid.key: Int(pid),
      ]
      if let displayID { payload[AXWire.Request.displayID.key] = displayID }
      return options.appendingPayload(to: payload)
    case let .readFrontmost(x, y, method, options, displayID):
      var payload: [String: Any] = [
        AXWire.Request.verb.key: AXWire.Verb.describe.rawValue,
        AXWire.Request.x.key: x,
        AXWire.Request.y.key: y,
        AXWire.Request.method.key: method.rawValue,
      ]
      if let displayID {
        payload[AXWire.Request.displayID.key] = displayID
      }
      return options.appendingPayload(to: payload)
    case let .hitTest(x, y, attributes, displayID):
      var payload: [String: Any] = [
        AXWire.Request.verb.key: AXWire.Verb.hitTest.rawValue,
        AXWire.Request.x.key: x,
        AXWire.Request.y.key: y,
      ]
      if let displayID {
        payload[AXWire.Request.displayID.key] = displayID
      }
      if let attributes, !attributes.isEmpty {
        payload[AXWire.Request.attributes.key] = attributes
      }
      return payload
    case let .write(request):
      return request.payload
    case let .deviceSettingRead(setting):
      return [
        AXWire.Request.verb.key: AXWire.Verb.settingsGet.rawValue,
        AXWire.Request.setting.key: setting,
      ]
    case let .deviceSettingWrite(setting, enabled):
      return [
        AXWire.Request.verb.key: AXWire.Verb.settingsSet.rawValue,
        AXWire.Request.setting.key: setting,
        AXWire.Request.enabled.key: enabled,
      ]
    case let .quiescence(pid, busyThresholdMs, quietWindowMs, displayID):
      var payload: [String: Any] = [AXWire.Request.verb.key: AXWire.Verb.quiet.rawValue]
      payload[AXWire.Request.pid.key] = pid.map { Int($0) }
      payload[AXWire.Request.busyThresholdMs.key] = busyThresholdMs
      payload[AXWire.Request.quietWindowMs.key] = quietWindowMs
      payload[AXWire.Request.displayID.key] = displayID
      return payload
    case .displays:
      return [AXWire.Request.verb.key: AXWire.Verb.displays.rawValue]
    }
  }
}
