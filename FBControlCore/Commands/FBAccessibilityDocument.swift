/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// The canonical name of a UI-automation backend: the value the `complete` document carries, and the
/// token a consumer selects a backend by. Named here rather than reusing the backend enum itself,
/// because that enum belongs to the simulator layer, which maps its cases to and from these names —
/// both directions live on `FBUIAutomationBackend`, pinned as a total bijection over `allCases`.
public enum FBUIAutomationBackendName: String, Sendable, Encodable, CaseIterable {
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

public extension FBAccessibilityFrame {
  /// The rectangle this frame describes, or `nil` when any edge was not representable.
  ///
  /// Each edge degrades to `nil` independently, but a rectangle missing one is not a smaller rectangle
  /// — it is no rectangle. A geometric consumer gets nothing rather than a plausible wrong shape.
  var rect: CGRect? {
    guard let x, let y, let width, let height else {
      return nil
    }
    return CGRect(x: x, y: y, width: width, height: height)
  }
}

/// The bounds a read's frames are relative to.
public struct FBAccessibilityScreenInfo: Sendable, Equatable, Encodable {

  public let width: Double
  public let height: Double
  public let coordinateSpace: FBAccessibilityCoordinateSpace

  /// A non-finite bound has no JSON form and is reported as unknown, the same normalization
  /// `FBAccessibilityFrame` applies to an edge. An off-screen element can report one, so the encoder
  /// must never be handed it: it would throw and fail the entire read.
  public init?(width: Double, height: Double, coordinateSpace: FBAccessibilityCoordinateSpace = .screen) {
    guard width.isFinite, height.isFinite else {
      return nil
    }
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
    let x = Double(point.x)
    let y = Double(point.y)
    return FBAccessibilityTargetDescriptor(kind: .point, x: x.isFinite ? x : nil, y: y.isFinite ? y : nil)
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

/// How much of the screen a read's element frames cover, measured along several dimensions.
///
/// One ratio was not enough to answer the question coverage exists for. Every backend exposes a chain
/// of full-screen containers — a window, an application element, a stack of layout groups — so a ratio
/// over *every* element saturates at `1.0` on almost any real screen and discriminates nothing. The
/// signal is in the **spread** between these:
///
/// - `walked` high and `content` low is a container-heavy tree: plenty of structure, little that a
///   user can actually perceive.
/// - `leaf` high and `content` low is area the app draws but does not describe — the unexposed WebView
///   case that motivated collecting coverage in the first place.
/// - `frame` far below `walked` means the caller's `--filter` hid most of what was read, which is a
///   fact about the request rather than about the screen.
///
/// Every ratio comes from the same grid over the same single walk, differing only in which subset of
/// elements is marked into it, so the set costs no extra traversal and no extra IPC over reporting one.
public struct FBAccessibilityCoverage: Sendable, Equatable, Encodable {

  /// Coverage of the elements the read *reports* — what a consumer actually receives.
  public let frame: Double

  /// Coverage of the elements the read *walked*, before `--filter` narrowed them. Equal to `frame`
  /// under the default filter, which drops nothing.
  ///
  /// Named for the walk rather than for the tree because the two are not always the same: the guest
  /// backends bound their walk by depth and node count, and a read that hit those bounds reports
  /// `truncated` and never saw the rest of the tree. This is what was read, which is the most any
  /// calculation over the result can honestly claim.
  ///
  /// The pair is the useful signal. A `frame` far below `walked` means the filter hid most of the
  /// screen's content; both being low means the app is not exposing it in the first place — a WebView
  /// or other remote content.
  public let walked: Double

  /// Coverage of the walked elements a user could actually perceive: those carrying a label and having
  /// no children.
  ///
  /// Both halves are load-bearing, and each is what makes the number survive a real tree.
  ///
  /// **Labelled, not identified.** An identifier is a developer handle for automation — `app-window`,
  /// `scroll-view`, the identifier on an unexposed `WKWebView`. It says nothing about whether a user can
  /// perceive anything there, so counting it reports an empty WebView as fully covered, which is the
  /// exact condition coverage exists to detect. A label is what a user perceives.
  ///
  /// **Innermost, not merely childless.** A label is disowned by a *labelled* descendant, not by having
  /// children at all. Counting a labelled ancestor would let a single window carrying a title cover the
  /// screen on its own, since coverage is a union of areas and one full-screen element saturates it.
  /// Requiring childlessness instead goes too far the other way: an app icon is a labelled button
  /// wrapping an unlabelled image, so a home screen full of them would measure zero.
  ///
  /// Measured over the walk, not over what `--filter` left behind, so it answers the same question
  /// whatever the caller asked to be *shown*.
  ///
  /// `nil` for a flat read, which carries no `children` and so cannot tell a leaf from a container.
  public let content: Double?

  /// Coverage of the walked elements with no children, labelled or not. Read against `content`: a `leaf`
  /// far above `content` is unlabelled leaf area — a region the app draws but does not describe.
  /// `nil` for a flat read, for the same reason.
  public let leaf: Double?

  /// Coverage found by grid hit-testing for remote (separate-process) content, when that ran.
  public let additional: Double?

  public init(frame: Double, walked: Double, content: Double?, leaf: Double?, additional: Double?) {
    self.frame = frame
    self.walked = walked
    self.content = content
    self.leaf = leaf
    self.additional = additional
  }

  enum CodingKeys: String, CodingKey {
    case frame
    case walked
    case content
    case leaf
    case additional
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(frame, forKey: .frame)
    try container.encode(walked, forKey: .walked)
    try container.encode(content, forKey: .content)
    try container.encode(leaf, forKey: .leaf)
    try container.encode(additional, forKey: .additional)
  }
}

/// Whether an element can be acted on, and — when it cannot — why.
///
/// One field rather than a handful of raw booleans, because the raw values are only meaningful in
/// combination and publishing them separately invites the naive conjunction that `enabled` already
/// suffers from. Automation asks one question; this answers it.
///
/// A sum type, so **the point exists only on the actionable case**. There is no representable state in
/// which a caller holds a tap point for an element it cannot tap, and none in which a reason sits beside
/// a point that contradicts it. It also keeps the accessibility server's `(-1, -1)` "nothing is
/// reachable" sentinel off the wire entirely: no reachable point is the *absence* of `.actionable`,
/// not a magic coordinate every consumer has to know to test for.
///
/// **`.actionable` must not be read as "a tap will land".** It is derived from the application's own
/// render tree, which cannot see another process compositing on top of it — a system alert or SpringBoard
/// chrome over the app does not change any of these attributes. What it warrants is narrower and exact:
/// nothing *this application* knows about blocks interaction, and `at` is where the application believes
/// a touch reaches. Naming an occluder in another process needs a hit-test, which is what
/// `FBAXKeys.occludedBy` buys.
public enum FBAccessibilityInteractable: Sendable, Equatable {

  /// The element can be acted on, at this point. Not necessarily the frame centre: for a partially
  /// covered element the centre is exactly what fails, and this is the point that does not.
  case actionable(at: FBAccessibilityPoint)

  /// The element cannot be acted on, for at least one reason. Never empty — an empty reason list is the
  /// actionable case, and the type makes that unrepresentable.
  case blocked(reasons: [Reason])

  /// Why an element cannot be acted on. A closed vocabulary, each case traceable to an attribute that was
  /// actually read rather than to a heuristic over geometry.
  public enum Reason: Sendable, Equatable {
    /// The accessibility server reports no reachable point on the element at all. Covers being covered
    /// outright, clipped by an ancestor, fully transparent, or scrolled out of its container — which of
    /// those it is cannot be told apart from this attribute alone.
    case notHittable
    /// The element has a reachable point, but it is not the centre — so the centre is covered, and
    /// automation aiming there hits whatever is on top. `by` names that element when a hit-test was paid
    /// for, and is nil otherwise.
    case occluded(by: FBAccessibilityOccluder?)
    /// The view has `userInteractionEnabled` off.
    case userInteractionDisabled
    /// The element reports itself disabled.
    case disabled
    /// The element declares itself hidden from accessibility.
    case hidden
    /// The element has no area to tap.
    case zeroSize
    /// Part of the element's frame lies outside the screen.
    ///
    /// A geometric fact rather than a claim about cause — it accumulates alongside whatever else blocks
    /// the element rather than replacing it, because being clipped by the edge and being covered are not
    /// alternatives and an element is often both. It earns a place in the vocabulary by licensing a
    /// recovery none of the others do: bring the element fully into view and try again.
    ///
    /// The accessibility server never reports this. It is not "off screen" — an element entirely outside
    /// the screen is absent from the tree altogether, which is the server behaving correctly — but the
    /// partially-clipped case is both real and common, and is plain geometry against the screen bounds
    /// the document already carries.
    case clippedByScreen
  }
}

/// A point in the same screen space element frames are expressed in.
public struct FBAccessibilityPoint: Sendable, Equatable, Encodable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  /// Nil when either coordinate is not representable, for the reason `FBAccessibilityFrame` normalizes
  /// its edges: a point missing one coordinate is not a nearer point, it is no point.
  public init?(_ point: CGPoint) {
    guard point.x.isFinite, point.y.isFinite else {
      return nil
    }
    self.init(x: Double(point.x), y: Double(point.y))
  }
}

/// The element found covering another element's centre. Descriptive rather than a handle: a hit-test
/// resolves an element with no identity that outlives the call, so what can honestly be reported is what
/// it looked like.
public struct FBAccessibilityOccluder: Sendable, Equatable, Encodable {
  public let type: String?
  public let identifier: String?
  public let label: String?
  public let frame: FBAccessibilityFrame?
  public let pid: Int64?

  public init(type: String?, identifier: String?, label: String?, frame: FBAccessibilityFrame?, pid: Int64?) {
    self.type = type
    self.identifier = identifier
    self.label = label
    self.frame = frame
    self.pid = pid
  }

  enum CodingKeys: String, CodingKey {
    case type
    case identifier
    case label
    case frame
    case pid
  }

  // Every key emitted, `null` where absent, so the shape does not vary with what the hit-test could read.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encode(identifier, forKey: .identifier)
    try container.encode(label, forKey: .label)
    try container.encode(frame, forKey: .frame)
    try container.encode(pid, forKey: .pid)
  }
}

public extension FBAccessibilityInteractable {

  /// The union is **internally tagged**: every value is an object and the shapes differ by case, so a
  /// consumer discriminates on `status` rather than probing for which key happens to be present.
  ///
  /// A literal tag is what lets TypeScript — the main consumer — narrow the union; probing for `at` would
  /// read a malformed or future payload as blocked; and a third case can later be added additively
  /// instead of breaking discrimination.
  enum CodingKeys: String, CodingKey {
    case status
    case at
    case reasons
  }

  enum Status: String, Sendable, Encodable {
    case actionable
    case blocked
  }
}

extension FBAccessibilityInteractable: Encodable {
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .actionable(at):
      try container.encode(Status.actionable, forKey: .status)
      try container.encode(at, forKey: .at)
    case let .blocked(reasons):
      try container.encode(Status.blocked, forKey: .status)
      try container.encode(reasons, forKey: .reasons)
    }
  }
}

extension FBAccessibilityInteractable.Reason: Encodable {

  /// `kind` rather than `reason`, so a member of `reasons` does not read as `{"reason": …}` repeated.
  enum CodingKeys: String, CodingKey {
    case kind
    case by
  }

  /// The wire spelling of each reason. Pinned by test — these are the tokens a consumer branches on.
  public var kind: String {
    switch self {
    case .notHittable: return "not_hittable"
    case .occluded: return "occluded"
    case .userInteractionDisabled: return "user_interaction_disabled"
    case .disabled: return "disabled"
    case .hidden: return "hidden"
    case .zeroSize: return "zero_size"
    case .clippedByScreen: return "clipped_by_screen"
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    // `by` is emitted only by the case that can have one, and only when a hit-test named it — the reason
    // the occluder lives on the case rather than beside it.
    if case let .occluded(by) = self, let by {
      try container.encode(by, forKey: .by)
    }
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
  /// Whether the element can be acted on, and why not when it cannot. `.some(nil)` — an explicit `null` —
  /// on a backend that cannot answer: the legacy accessibility path has no counterpart for the attributes
  /// this is derived from, and saying so is what keeps the key set fixed across backends.
  public var interactable: FBAccessibilityInteractable??
  public var customActions: [String]??
  public var traits: [String]??
  public var pid: Int64??
  /// The raw role (`AXButton`) and the stringified frame. `complete` reports these through `type` and
  /// `frame` instead, so they are absent from its `CodingKeys` — they exist for the legacy spelling,
  /// which emits both.
  public var role: String??
  public var axFrame: String??
  /// The nested children, or `nil` when the read did not walk them — a flat read lists every node
  /// separately and carries no `children` key at all. Not an attribute: it comes from the traversal.
  ///
  /// A format that asks for a tree reports this on every element (see `reportingChildren()`); the flat
  /// format reports it on none. Either way the key set does not vary with the backend.
  public var children: [FBAccessibilityDocumentElement]?

  /// A copy that reports `children` on every node, empty where the read walked none.
  ///
  /// How much of a subtree a single-element read walks differs by backend — the accessibility backend
  /// can walk its element's children, while the guest-backed readers resolve one node from a hit-test
  /// and never look further. Left alone that difference reaches the output, so the same
  /// command describes the same element with a different key set depending on `--api`. Normalizing here
  /// keeps the shape fixed while letting the contents say what each backend actually read: the key is
  /// always present, and an empty array means "no children in what was read".
  public func reportingChildren() -> FBAccessibilityDocumentElement {
    var copy = self
    copy.children = (children ?? []).map { $0.reportingChildren() }
    return copy
  }

  public init(children: [FBAccessibilityDocumentElement]? = nil) {
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
    case interactable
    case customActions = "custom_actions"
    case traits
    case pid
    case children
  }

}

/// An element's `value`, which the platform reports as an untyped object — usually a string, sometimes
/// a number or a flag (a slider's position, a switch's state), and occasionally a collection.
///
/// This is the one attribute whose shape the platform does not fix, so it is the one place a value tree
/// is warranted. It stays a closed set scoped to this attribute rather than a general-purpose JSON type:
/// nothing else in the schema is dynamic.
public enum FBAccessibilityAttributeValue: Sendable, Equatable, Encodable {
  case string(String)
  case bool(Bool)
  case int(Int64)
  case double(Double)
  case array([FBAccessibilityAttributeValue])
  case object([String: FBAccessibilityAttributeValue])
  /// A null held *inside* a collection. Absence at the top level is carried by the element's own
  /// optional, so this case exists only for the position where that optional cannot reach.
  case null

  /// Classifies the platform's untyped `accessibilityValue`. Collections are carried through as
  /// collections — flattening one to its `String(describing:)` form would change what a consumer reads.
  /// An object of no recognized kind does become that description, which is the long-standing fallback.
  ///
  /// Fails only for `nil`/`NSNull`, which is how a caller reading a single attribute distinguishes "no
  /// value" — see `member(_:)` for why a collection cannot use that same signal.
  public init?(_ object: Any?) {
    guard let object, !(object is NSNull) else {
      return nil
    }
    switch object {
    case let value as String:
      self = .string(value)
    case let value as NSNumber:
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        self = .bool(value.boolValue)
      } else {
        let objCType = String(cString: value.objCType)
        self = (objCType == "f" || objCType == "d") ? .double(value.doubleValue) : .int(value.int64Value)
      }
    case let value as [Any]:
      self = .array(value.map(Self.member))
    case let value as [String: Any]:
      self = .object(value.mapValues(Self.member))
    default:
      self = .string(String(describing: object))
    }
  }

  /// A member of a collection value. `init?` reports `nil` only for `nil`/`NSNull` — every other object
  /// classifies, falling back to its description — so a failure here means the member was null, and a
  /// null that is a member of a collection has to stay in place rather than read as an absent value.
  private static func member(_ object: Any) -> FBAccessibilityAttributeValue {
    FBAccessibilityAttributeValue(object) ?? .null
  }

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
    case let .array(value):
      try container.encode(value)
    case let .object(value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
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
  public let backend: FBUIAutomationBackendName?
  public let target: FBAccessibilityTargetDescriptor?
  public let profile: FBAccessibilityProfilingData?
  public let coverage: FBAccessibilityCoverage?

  public init(
    elements: [FBAccessibilityDocumentElement],
    modal: FBAccessibilityModalInfo? = nil,
    truncated: Bool = false,
    screen: FBAccessibilityScreenInfo? = nil,
    backend: FBUIAutomationBackendName? = nil,
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

public extension FBAccessibilityDocumentElement {
  /// The value a marker match reads for `key`. A marker is matched over the *serialized* element, so an
  /// attribute the read did not carry simply does not match.
  func searchableValue(for key: FBAXSearchableKey) -> String? {
    switch key {
    case .label: return label ?? nil
    case .uniqueID: return identifier ?? nil
    case .value:
      guard case let .string(string)? = (value ?? nil) else { return nil }
      return string
    case .title: return title ?? nil
    case .role: return role ?? nil
    case .roleDescription: return roleDescription ?? nil
    case .subrole: return subrole ?? nil
    case .help: return help ?? nil
    case .placeholder: return placeholder ?? nil
    }
  }
}

/// What a read produced: a whole tree, a single element, or nothing.
///
/// The distinction is real and observable — a point or marker read emits a bare object where a
/// whole-tree read emits an array — so it is modelled rather than left implicit in the shape of an
/// untyped payload. `complete` flattens all three to an array; the legacy formats preserve them.
public enum FBAccessibilityElementPayload: Sendable, Equatable {
  case tree([FBAccessibilityDocumentElement])
  case single(FBAccessibilityDocumentElement)
  /// A hit-test that found nothing: a successful empty result, distinct from a failed read.
  case empty

  /// A copy whose elements all report `children`, for the formats that describe a tree.
  public func reportingChildren() -> FBAccessibilityElementPayload {
    switch self {
    case let .tree(elements): return .tree(elements.map { $0.reportingChildren() })
    case let .single(element): return .single(element.reportingChildren())
    case .empty: return .empty
    }
  }

  /// The elements as a list, which is how `complete` always reports them.
  public var elements: [FBAccessibilityDocumentElement] {
    switch self {
    case let .tree(elements): return elements
    case let .single(element): return [element]
    case .empty: return []
    }
  }
}

public extension FBAccessibilityElementPayload {
  /// The legacy-spelled elements as a Foundation object.
  ///
  /// The legacy formats are rendered by `JSONSerialization`, not by `JSONEncoder`, and the difference is
  /// not cosmetic: the two disagree on how a non-integral double is written. `JSONSerialization` emits
  /// the full 17 significant digits (`0.33333333333333331`) where `JSONEncoder` emits the shortest form
  /// that round-trips (`0.3333333333333333`). Sub-point frame edges and fractional element values are
  /// commonplace, so encoding these through `JSONEncoder` would silently change the bytes of a format
  /// whose output consumers already parse. The typed model stays the source of truth; this is only
  /// about which writer produces the frozen wire form.
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
  /// This element under the legacy key names, as Foundation. A requested attribute is present — `NSNull`
  /// when it has no value — and an unrequested one is absent, the same three states the typed model
  /// carries.
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
  /// Every edge is present, `NSNull` where it is not representable.
  var legacyFoundationObject: [String: Any] {
    ["x": x ?? NSNull(), "y": y ?? NSNull(), "width": width ?? NSNull(), "height": height ?? NSNull()]
  }
}

public extension FBAccessibilityInteractable {
  /// The same internally-tagged shape the `complete` encoder emits, as Foundation.
  ///
  /// Rendered by hand rather than through `JSONEncoder` for the reason the legacy formats exist at all:
  /// they are written by `JSONSerialization`, and the two writers disagree on how a non-integral double
  /// is spelled. Reusing the encoder here would change the bytes of a frozen format.
  var legacyFoundationObject: [String: Any] {
    switch self {
    case let .actionable(at):
      return ["status": Status.actionable.rawValue, "at": ["x": at.x, "y": at.y]]
    case let .blocked(reasons):
      return ["status": Status.blocked.rawValue, "reasons": reasons.map { $0.legacyFoundationObject }]
    }
  }
}

public extension FBAccessibilityInteractable.Reason {
  var legacyFoundationObject: [String: Any] {
    guard case let .occluded(by) = self, let by else {
      return ["kind": kind]
    }
    return ["kind": kind, "by": by.legacyFoundationObject]
  }
}

public extension FBAccessibilityOccluder {
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
