/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// Which backend produced a read. Named here rather than reusing the backend enum itself, because that
/// enum belongs to the simulator layer and this is the value the *document* carries; the simulator
/// layer maps its own cases onto these names.
public enum FBAccessibilityBackendName: String, Sendable, CaseIterable, Encodable {
  case ax
  case axBridge = "axbridge"
  case axBridgePersistent = "axbridge-persistent"
  case testmanagerd
}

/// The space an element frame is expressed in. A single case today; it exists so that a read expressed
/// against something other than the whole screen has a place to say so, rather than callers having to
/// infer it.
public enum FBAccessibilityCoordinateSpace: String, Sendable, Encodable {
  case screen
}

/// An element's on-screen rectangle.
///
/// Each edge is optional because an off-screen element can report a non-finite coordinate, which JSON
/// cannot represent. Those are normalized to `nil` at construction — once — so nothing downstream has
/// to re-check, and the encoder cannot be handed a value it would refuse.
public struct FBAccessibilityFrame: Sendable, Equatable, Encodable {

  public let x: Double?
  public let y: Double?
  public let width: Double?
  public let height: Double?

  public init(x: Double?, y: Double?, width: Double?, height: Double?) {
    self.x = Self.finite(x)
    self.y = Self.finite(y)
    self.width = Self.finite(width)
    self.height = Self.finite(height)
  }

  public init(_ rect: CGRect) {
    self.init(
      x: Double(rect.origin.x), y: Double(rect.origin.y),
      width: Double(rect.size.width), height: Double(rect.size.height)
    )
  }

  private static func finite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else {
      return nil
    }
    return value
  }

  enum CodingKeys: String, CodingKey {
    case x
    case y
    case width
    case height
  }

  // Every edge is emitted, `null` where it is not representable, so the frame's shape never varies.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(x, forKey: .x)
    try container.encode(y, forKey: .y)
    try container.encode(width, forKey: .width)
    try container.encode(height, forKey: .height)
  }
}

/// The bounds a read's frames are relative to.
public struct FBAccessibilityScreenInfo: Sendable, Equatable, Encodable {

  public let width: Double
  public let height: Double
  public let coordinateSpace: FBAccessibilityCoordinateSpace

  public init(width: Double, height: Double, coordinateSpace: FBAccessibilityCoordinateSpace = .screen) {
    self.width = width
    self.height = height
    self.coordinateSpace = coordinateSpace
  }

  enum CodingKeys: String, CodingKey {
    case width
    case height
    case coordinateSpace = "coordinate_space"
  }
}

/// What a read was asked for. This is how a consumer tells one describe verb from another: every verb
/// emits the same document shape, so the *target* rather than the shape identifies the read.
public struct FBAccessibilityTargetDescriptor: Sendable, Equatable, Encodable {

  public enum Kind: String, Sendable, Encodable {
    case frontmost
    case application
    case point
    case marker
  }

  public let kind: Kind
  /// The process the read was anchored to, for `.application`.
  public let pid: Int32?
  /// The coordinate hit-tested, for `.point`.
  public let x: Double?
  public let y: Double?
  /// The searched-for substring, for `.marker`.
  public let value: String?
  /// The element key the marker was matched against, for `.marker`.
  public let matchKey: String?

  public init(
    kind: Kind,
    pid: Int32? = nil,
    x: Double? = nil,
    y: Double? = nil,
    value: String? = nil,
    matchKey: String? = nil
  ) {
    self.kind = kind
    self.pid = pid
    self.x = x
    self.y = y
    self.value = value
    self.matchKey = matchKey
  }

  public static let frontmost = FBAccessibilityTargetDescriptor(kind: .frontmost)

  public static func application(pid: pid_t) -> FBAccessibilityTargetDescriptor {
    FBAccessibilityTargetDescriptor(kind: .application, pid: Int32(pid))
  }

  public static func point(_ point: CGPoint) -> FBAccessibilityTargetDescriptor {
    FBAccessibilityTargetDescriptor(kind: .point, x: Double(point.x), y: Double(point.y))
  }

  public static func marker(value: String, matchKey: String) -> FBAccessibilityTargetDescriptor {
    FBAccessibilityTargetDescriptor(kind: .marker, value: value, matchKey: matchKey)
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case pid
    case x
    case y
    case value
    case matchKey = "match_key"
  }

  // `encode` rather than `encodeIfPresent`: every key is emitted, `null` where it does not apply to
  // this kind, so the document's shape does not vary with the verb that produced it.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    try container.encode(pid, forKey: .pid)
    try container.encode(x, forKey: .x)
    try container.encode(y, forKey: .y)
    try container.encode(value, forKey: .value)
    try container.encode(matchKey, forKey: .matchKey)
  }
}

/// The proportion of the screen covered by element frames.
public struct FBAccessibilityCoverage: Sendable, Equatable, Encodable {

  public let frame: Double
  /// Coverage found by grid hit-testing for remote (separate-process) content, when that ran.
  public let additional: Double?

  public init(frame: Double, additional: Double?) {
    self.frame = frame
    self.additional = additional
  }

  enum CodingKeys: String, CodingKey {
    case frame
    case additional
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(frame, forKey: .frame)
    try container.encode(additional, forKey: .additional)
  }
}

/// An accessibility element in the `complete` output format.
///
/// A struct rather than an untyped bag: every attribute the schema can carry is a named, typed field.
///
/// Each attribute is doubly optional, which is how `Encodable` expresses the three states a read can
/// produce — the synthesized encoder writes optionals with `encodeIfPresent`, so this needs no encoder
/// of its own:
///
/// - `nil` — never requested, so the key is omitted entirely.
/// - `.some(nil)` — requested, but the element has no value: an explicit `null`.
/// - `.some(value)` — the value.
///
/// That is the same distinction the legacy formats draw with key presence, and it is worth keeping:
/// collapsing the first two would leave a consumer unable to tell "not asked for" from "asked for and
/// empty", and would stop `--key` trimming the payload it exists to trim.
///
/// The envelope around these elements still has a fixed key set — that shape must not vary with the
/// verb. Which *attributes* an element carries is a caller's explicit choice, which is a different
/// thing.
///
/// The names here are the clean schema: the `AX`-prefixed legacy spellings become plain ones
/// (`AXLabel` to `label`, `AXUniqueId` to `identifier`), and the two attributes that merely restate
/// another are absent entirely — the stringified frame (`frame` carries it structurally) and the raw
/// role (`type` is its normalized form).
public struct FBAccessibilityDocumentElement: Sendable, Equatable, Encodable {

  public var label: String??
  public var value: FBAccessibilityAttributeValue??
  public var identifier: String??
  public var type: String??
  public var title: String??
  public var help: String??
  public var roleDescription: String??
  public var subrole: String??
  public var placeholder: String??
  public var frame: FBAccessibilityFrame??
  public var enabled: Bool??
  public var contentRequired: Bool??
  public var expanded: Bool??
  public var hidden: Bool??
  public var focused: Bool??
  public var isRemote: Bool??
  public var customActions: [String]??
  public var traits: [String]??
  public var pid: Int64??
  /// Always reported: children come from the traversal, not from an attribute read.
  public var children: [FBAccessibilityDocumentElement]

  public init(children: [FBAccessibilityDocumentElement] = []) {
    self.children = children
  }

  enum CodingKeys: String, CodingKey {
    case label
    case value
    case identifier
    case type
    case title
    case help
    case roleDescription = "role_description"
    case subrole
    case placeholder
    case frame
    case enabled
    case contentRequired = "content_required"
    case expanded
    case hidden
    case focused
    case isRemote = "is_remote"
    case customActions = "custom_actions"
    case traits
    case pid
    case children
  }

}

/// An element's `value`, which the platform reports as an untyped object — usually a string, sometimes
/// a number or a flag (a slider's position, a switch's state).
///
/// A closed set of the shapes that attribute actually takes, rather than an open JSON value: it keeps
/// the reported type intact without letting arbitrary structure into the schema.
public enum FBAccessibilityAttributeValue: Sendable, Equatable, Encodable {
  case string(String)
  case bool(Bool)
  case int(Int64)
  case double(Double)

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .string(value):
      try container.encode(value)
    case let .bool(value):
      try container.encode(value)
    case let .int(value):
      try container.encode(value)
    case let .double(value):
      // JSON cannot represent a non-finite number; report it as absent rather than fail the encode.
      try value.isFinite ? container.encode(value) : container.encodeNil()
    }
  }
}

/// The `complete` output format: the elements plus everything the read learned about the state they
/// were read in.
///
/// **The key set is fixed.** Every field is always encoded, and anything a particular verb or backend
/// cannot supply is an explicit `null` rather than an absent key. That is what lets one parser serve
/// every describe verb: a point read and a whole-tree read differ in their *values*, never in their
/// shape, and `target` rather than the shape says which verb produced the document. `elements` is
/// always an array for the same reason, even for the single-element reads the legacy envelope emits as
/// a bare object.
///
/// The document is expected to grow. New fields are added additively and consumers are expected to
/// ignore ones they do not know, so there is deliberately no version field to bump.
public struct FBAccessibilityDocument: Sendable, Encodable {

  public let elements: [FBAccessibilityDocumentElement]
  public let modal: FBAccessibilityModalInfo?
  public let truncated: Bool
  public let screen: FBAccessibilityScreenInfo?
  public let backend: FBAccessibilityBackendName?
  public let target: FBAccessibilityTargetDescriptor?
  public let profile: FBAccessibilityProfilingData?
  public let coverage: FBAccessibilityCoverage?

  public init(
    elements: [FBAccessibilityDocumentElement],
    modal: FBAccessibilityModalInfo? = nil,
    truncated: Bool = false,
    screen: FBAccessibilityScreenInfo? = nil,
    backend: FBAccessibilityBackendName? = nil,
    target: FBAccessibilityTargetDescriptor? = nil,
    profile: FBAccessibilityProfilingData? = nil,
    coverage: FBAccessibilityCoverage? = nil
  ) {
    self.elements = elements
    self.modal = modal
    self.truncated = truncated
    self.screen = screen
    self.backend = backend
    self.target = target
    self.profile = profile
    self.coverage = coverage
  }

  enum CodingKeys: String, CodingKey {
    case elements
    case modal
    case truncated
    case screen
    case backend
    case target
    case profile
    case coverage
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(elements, forKey: .elements)
    try container.encode(modal, forKey: .modal)
    try container.encode(truncated, forKey: .truncated)
    try container.encode(screen, forKey: .screen)
    try container.encode(backend, forKey: .backend)
    try container.encode(target, forKey: .target)
    try container.encode(profile, forKey: .profile)
    try container.encode(coverage, forKey: .coverage)
  }
}
