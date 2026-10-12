/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The guest's answer to a `displays` request: the displays it can address, and which reads and writes
/// it can scope to one of them.
public struct BridgeAXDisplayInventory: Codable, Equatable, Sendable {
  public struct Display: Codable, Equatable, Sendable {
    public enum CodingKeys: String, CodingKey {
      case uniqueID
      case displayID
    }

    public let uniqueID: String
    public let displayID: UInt32

    public init(uniqueID: String, displayID: UInt32) {
      self.uniqueID = uniqueID
      self.displayID = displayID
    }
  }

  public enum CodingKeys: String, CodingKey {
    case displayScopedInteractions
    case displayScopedTrees
    case displayScopedQuiescence
    case displays
  }

  public let displayScopedInteractions: Bool
  public let displayScopedTrees: Bool
  public let displayScopedQuiescence: Bool
  public let displays: [Display]

  public init(displayScopedInteractions: Bool, displayScopedTrees: Bool, displayScopedQuiescence: Bool, displays: [Display]) {
    self.displayScopedInteractions = displayScopedInteractions
    self.displayScopedTrees = displayScopedTrees
    self.displayScopedQuiescence = displayScopedQuiescence
    self.displays = displays
  }

  /// A capability the response does not mention is one the guest does not advertise.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    displayScopedInteractions = try container.decodeIfPresent(Bool.self, forKey: .displayScopedInteractions) ?? false
    displayScopedTrees = try container.decodeIfPresent(Bool.self, forKey: .displayScopedTrees) ?? false
    displayScopedQuiescence = try container.decodeIfPresent(Bool.self, forKey: .displayScopedQuiescence) ?? false
    displays = try container.decode([Display].self, forKey: .displays)
  }

  /// The fields of a successful response, for the guest to send beside `ok`.
  public var payload: [String: Any] {
    [
      CodingKeys.displayScopedInteractions.stringValue: displayScopedInteractions,
      CodingKeys.displayScopedTrees.stringValue: displayScopedTrees,
      CodingKeys.displayScopedQuiescence.stringValue: displayScopedQuiescence,
      CodingKeys.displays.stringValue: displays.map { display -> [String: Any] in
        [Display.CodingKeys.uniqueID.stringValue: display.uniqueID, Display.CodingKeys.displayID.stringValue: display.displayID]
      },
    ]
  }
}

/// A fullscreen modal the guest found in a tree it read: a system alert, or an alert the application
/// presented itself.
public struct BridgeAXModal: Codable, Equatable, Sendable {
  /// Who owns the modal: the system shell (SpringBoard — a system or permission alert) or the app itself
  /// (an in-app `UIAlertController`).
  public enum Kind: String, Codable, Sendable {
    case system
    case app
  }

  public enum CodingKeys: String, CodingKey {
    case kind
    case elementType
    case label
  }

  public let kind: Kind

  /// The concrete accessibility element class of the alert, e.g. `SBAlertItemWindow` (system) or
  /// `_UIAlertControllerPhoneTVMacView` (UIKit alert).
  public let elementType: String

  /// The alert's title or primary label, when the guest could read one.
  public let label: String?

  public init(kind: Kind, elementType: String, label: String?) {
    self.kind = kind
    self.elementType = elementType
    self.label = label
  }

  /// Decodes the descriptor `payload` produces; nil when a required field is absent or not a known value.
  public init?(payload: [String: Any]) {
    guard let kindValue = payload[CodingKeys.kind.stringValue] as? String,
      let kind = Kind(rawValue: kindValue),
      let elementType = payload[CodingKeys.elementType.stringValue] as? String
    else {
      return nil
    }
    self.init(kind: kind, elementType: elementType, label: payload[CodingKeys.label.stringValue] as? String)
  }

  public var payload: [String: String] {
    var payload = [CodingKeys.kind.stringValue: kind.rawValue, CodingKeys.elementType.stringValue: elementType]
    payload[CodingKeys.label.stringValue] = label
    return payload
  }
}
