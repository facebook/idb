/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum SimulatorDisplayInteractionError: Error, LocalizedError {
  case unsupportedCapability(String)
  case inactiveDisplay(String)
  case missingMapping(String)
  case invalidPoint(CGPoint, bounds: CGSize)
  case nonFinitePoint(CGPoint)

  public var errorDescription: String? {
    switch self {
    case let .unsupportedCapability(capability): "Simulator does not support \(capability)"
    case let .inactiveDisplay(id): "Display \(id) is not the active integrated display"
    case let .missingMapping(id): "Display \(id) has no unique accessibility and touchscreen mapping"
    case let .invalidPoint(point, bounds):
      "Touch point (\(point.x), \(point.y)) \(Self.invalidity(of: point)) the display's point bounds (\(bounds.width) x \(bounds.height))"
    case let .nonFinitePoint(point):
      "Touch point (\(point.x), \(point.y)) is not a real position (\(Self.nonFiniteAxes(of: point).joined(separator: ", ")))"
    }
  }

  private static func invalidity(of point: CGPoint) -> String {
    let nonFinite = nonFiniteAxes(of: point)
    if nonFinite.isEmpty { return "is outside" }
    return "is not a real position (\(nonFinite.joined(separator: ", "))) within"
  }

  private static func nonFiniteAxes(of point: CGPoint) -> [String] {
    [("x", point.x), ("y", point.y)].compactMap { axis, value in
      value.isNaN ? "\(axis) is NaN" : value.isInfinite ? "\(axis) is infinite" : nil
    }
  }
}

struct SimulatorAccessibilityDisplay: Decodable, Equatable, Sendable {
  let uniqueID: String
  let displayID: UInt32
}

/// What the guest advertises it can scope to a named display, beyond reporting its displays.
package struct AXBridgeDisplayCapabilities: OptionSet, Sendable {
  package let rawValue: Int

  package init(rawValue: Int) {
    self.rawValue = rawValue
  }

  package static let scopedInteractions = AXBridgeDisplayCapabilities(rawValue: 1 << 0)
  package static let scopedTrees = AXBridgeDisplayCapabilities(rawValue: 1 << 1)
  package static let scopedQuiescence = AXBridgeDisplayCapabilities(rawValue: 1 << 2)
}

enum AXBridgeDisplayInventory {
  static func decode(_ data: Data, requiring capabilities: AXBridgeDisplayCapabilities = []) throws -> [SimulatorAccessibilityDisplay] {
    if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      response["ok"] as? Bool == false, response["error_kind"] as? String == "capability_unavailable"
    {
      throw SimulatorDisplayInteractionError.unsupportedCapability("accessibility display discovery")
    }
    let response = try AXBridgeResponse.validated(data, context: "display inventory")
    if capabilities.contains(.scopedInteractions), response["displayScopedInteractions"] as? Bool != true {
      throw SimulatorDisplayInteractionError.unsupportedCapability("display-scoped accessibility interactions in this guest")
    }
    if capabilities.contains(.scopedTrees), response["displayScopedTrees"] as? Bool != true {
      throw SimulatorDisplayInteractionError.unsupportedCapability("display-scoped accessibility trees in this guest")
    }
    if capabilities.contains(.scopedQuiescence), response["displayScopedQuiescence"] as? Bool != true {
      throw SimulatorDisplayInteractionError.unsupportedCapability("display-scoped quiescence in this guest")
    }
    struct Envelope: Decodable {
      let displays: [SimulatorAccessibilityDisplay]
    }
    guard let displays = try? JSONDecoder().decode(Envelope.self, from: data).displays,
      displays.count <= 32,
      displays.allSatisfy({ !$0.uniqueID.isEmpty && $0.uniqueID.count <= 1024 && $0.displayID > 0 }),
      Set(displays.map(\.uniqueID)).count == displays.count,
      Set(displays.map(\.displayID)).count == displays.count
    else { throw AXBridgeError.guestFailure("Invalid accessibility display inventory") }
    return displays
  }
}
