/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// A node in the accessibility hierarchy returned by `describeAll()`.
///
/// This mirrors the accessibility serializer's default key set. Every field is
/// optional because any attribute may be absent for a given element; `children`
/// defaults to empty. `value` (`AXValue`) is rendered to a `String` by the
/// companion before it is sent, so it is a plain optional here.
public struct AXElement: Decodable, Sendable {

  /// The element's accessibility label (`AXLabel`).
  public let label: String?
  /// The element's value (`AXValue`).
  public let value: String?
  /// The element's accessibility identifier (`AXUniqueId`).
  public let uniqueID: String?
  /// The element's type (`type`) -- the role with any `AX` prefix stripped.
  public let type: String?
  /// The element's title (`title`).
  public let title: String?
  /// The element's help text (`help`).
  public let help: String?
  /// Whether the element is enabled (`enabled`).
  public let enabled: Bool?
  /// The element's custom action names (`custom_actions`).
  public let customActions: [String]?
  /// The element's accessibility role (`role`).
  public let role: String?
  /// The element's role description (`role_description`).
  public let roleDescription: String?
  /// The element's subrole (`subrole`).
  public let subrole: String?
  /// Whether the element requires content (`content_required`).
  public let contentRequired: Bool?
  /// The process id owning the element (`pid`).
  public let pid: Int?
  /// The element's accessibility traits (`traits`).
  public let traits: [String]?
  /// The element's child elements (`children`); empty when there are none.
  public let children: [AXElement]

  /// The element's frame in screen points (`frame`).
  public var frame: CGRect? {
    frameObject.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
  }

  /// Decoded backing for `frame`: the serializer emits `{x, y, width, height}`,
  /// which `CGRect` does not decode from on its own (its own coding shape differs).
  private let frameObject: FrameObject?

  private struct FrameObject: Decodable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
  }

  private enum CodingKeys: String, CodingKey {
    case label = "AXLabel"
    case value = "AXValue"
    case uniqueID = "AXUniqueId"
    case type
    case title
    case help
    case enabled
    case customActions = "custom_actions"
    case role
    case roleDescription = "role_description"
    case subrole
    case contentRequired = "content_required"
    case pid
    case traits
    case children
    case frameObject = "frame"
  }
}
