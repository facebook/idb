/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum FBAccessibilityElementPayload: Sendable, Equatable {
  case tree([FBAccessibilityDocumentElement])
  case single(FBAccessibilityDocumentElement)
  /// A point read that succeeded but hit nothing.
  case empty

  public func reportingChildren() -> FBAccessibilityElementPayload {
    switch self {
    case let .tree(elements): return .tree(elements.map { $0.reportingChildren() })
    case let .single(element): return .single(element.reportingChildren())
    case .empty: return .empty
    }
  }

  public var elements: [FBAccessibilityDocumentElement] {
    switch self {
    case let .tree(elements): return elements
    case let .single(element): return [element]
    case .empty: return []
    }
  }
}

public extension FBAccessibilityElementPayload {
  /// Foundation objects, so `JSONSerialization` reproduces the legacy format's floating-point rendering.
  var legacyFoundationObject: Any {
    switch self {
    case let .tree(elements):
      return elements.map { $0.legacyFoundationObject }
    case let .single(element):
      return element.legacyFoundationObject
    case .empty:
      return NSNull()
    }
  }
}

public extension FBAccessibilityDocumentElement {
  var legacyFoundationObject: [String: Any] {
    var object: [String: Any] = [:]
    func put(_ attribute: Any??, _ key: String) {
      guard let value = attribute else {
        return
      }
      object[key] = value ?? NSNull()
    }
    put(label, "AXLabel")
    put(axFrame, "AXFrame")
    put(value.map { $0?.legacyFoundationValue }, "AXValue")
    put(identifier, "AXUniqueId")
    put(type, "type")
    put(title, "title")
    put(frame.map { $0?.legacyFoundationObject }, "frame")
    put(help, "help")
    put(enabled, "enabled")
    put(customActions, "custom_actions")
    put(role, "role")
    put(roleDescription, "role_description")
    put(subrole, "subrole")
    put(contentRequired, "content_required")
    put(pid, "pid")
    put(traits, "traits")
    put(expanded, "expanded")
    put(placeholder, "placeholder")
    put(hidden, "hidden")
    put(focused, "focused")
    put(isRemote, "is_remote")
    put(interactable.map { $0?.legacyFoundationObject }, "interactable")
    if let children {
      object["children"] = children.map { $0.legacyFoundationObject }
    }
    return object
  }
}

public extension FBAccessibilityFrame {
  var legacyFoundationObject: [String: Any] {
    ["x": x ?? NSNull(), "y": y ?? NSNull(), "width": width ?? NSNull(), "height": height ?? NSNull()]
  }
}

public extension FBAccessibilityInteractable {
  var legacyFoundationObject: [String: Any] {
    switch self {
    case let .actionable(at):
      return ["status": Status.actionable.rawValue, "at": ["x": at.x, "y": at.y]]
    case let .blocked(reasons):
      return [
        "status": Status.blocked.rawValue,
        "reasons": reasons.mostSpecificFirst.map { $0.legacyFoundationObject },
      ]
    }
  }
}

public extension FBAccessibilityInteractable.Reason {
  var legacyFoundationObject: [String: Any] {
    switch self {
    case let .occluded(by), let .handledBy(by):
      guard let by else { return ["kind": kind] }
      return ["kind": kind, "by": by.legacyFoundationObject]
    default:
      return ["kind": kind]
    }
  }
}

public extension FBAccessibilityElementRef {
  var legacyFoundationObject: [String: Any] {
    [
      "type": type ?? NSNull(),
      "identifier": identifier ?? NSNull(),
      "label": label ?? NSNull(),
      "frame": frame?.legacyFoundationObject ?? NSNull(),
      "pid": pid ?? NSNull(),
    ]
  }
}

public extension FBAccessibilityAttributeValue {
  var legacyFoundationValue: Any {
    switch self {
    case let .string(value): return value
    case let .bool(value): return value
    case let .int(value): return value
    case let .double(value): return value.isFinite ? value : NSNull()
    case let .array(value): return value.map { $0.legacyFoundationValue }
    case let .object(value): return value.mapValues { $0.legacyFoundationValue }
    case .null: return NSNull()
    }
  }
}
