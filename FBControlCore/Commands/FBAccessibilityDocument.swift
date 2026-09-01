/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// The canonical name of a UI-automation backend: the value the `complete` document carries, and the
/// token a consumer selects a backend by. The simulator layer's backend enum maps to and from these names.
public enum FBUIAutomationBackendName: String, Sendable, Encodable, CaseIterable {
  case ax
  case axBridge = "axbridge"
  case axBridgePersistent = "axbridge-persistent"
  case axBridgeExclusive = "axbridge-exclusive"
  case testmanagerd
}

/// The space an element frame is expressed in.
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
/// Every ratio comes from the same grid over the same single walk, differing only in which subset of
/// elements is marked into it.
public struct FBAccessibilityCoverage: Sendable, Equatable, Encodable {

  /// Coverage of the elements the read *reports* — what a consumer actually receives.
  public let frame: Double

  /// Coverage of the elements the read *walked*, before `--filter` narrowed them. Equal to `frame`
  /// under the default filter, which drops nothing.
  ///
  /// Named for the walk rather than for the tree: the guest backends bound their walk by depth and
  /// node count, and a truncated read never saw the rest of the tree.
  ///
  /// A `frame` far below `walked` means the filter hid most of the screen's content; both being low
  /// means the app is not exposing it in the first place — a WebView or other remote content.
  public let walked: Double

  /// Coverage of the walked elements a user could perceive: those carrying a label with no labelled
  /// descendant.
  ///
  /// Labelled, not identified: an identifier is a developer handle and says nothing about what a user
  /// perceives. Innermost, not childless: a label is disowned only by a *labelled* descendant, so an
  /// app icon — a labelled button wrapping an unlabelled image — still counts.
  ///
  /// Measured over the walk, not over what `--filter` left behind. `nil` for a flat read, which
  /// carries no `children` and so cannot tell a leaf from a container.
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
/// A sum type, so **the point exists only on the actionable case**. There is no representable state in
/// which a caller holds a tap point for an element it cannot tap, and none in which a reason sits beside
/// a point that contradicts it. It also keeps the accessibility server's `(-1, -1)` "nothing is
/// reachable" sentinel off the wire entirely: no reachable point is the *absence* of `.actionable`,
/// not a magic coordinate every consumer has to know to test for.
///
/// `.actionable` does not mean "a tap will land": it is derived from the application's own render
/// tree, which cannot see another process compositing on top of it — a system alert or SpringBoard
/// chrome over the app does not change these attributes. It means nothing *this application* knows
/// about blocks interaction, and `at` is where the application believes a touch reaches. Naming an
/// occluder in another process requires the `FBAXKeys.occludedBy` hit-test.
public enum FBAccessibilityInteractable: Sendable, Equatable {

  /// The element can be acted on, at this point. Not necessarily the frame centre: for a partially
  /// covered element the centre is exactly what fails, and this is the point that does not.
  case actionable(at: FBAccessibilityPoint)

  /// The element cannot be acted on, for at least one reason. Never empty — an empty reason list is the
  /// actionable case, and the type makes that unrepresentable.
  ///
  /// **Ordered most specific first.** `reasons[0]` is the most actionable thing known about the element,
  /// so a consumer that reads only the first gets the best answer rather than an arbitrary one. The
  /// general observation `notHittable` — the accessibility server saying it found no reachable point,
  /// without saying why — always sorts last, behind anything that explains it.
  case blocked(reasons: [Reason])

  /// Why an element cannot be acted on. A closed vocabulary, each case traceable to an attribute that was
  /// actually read rather than to a heuristic over geometry.
  ///
  /// Every case but `notHittable` names a cause; `notHittable` only reports that the server found no
  /// reachable point. Reasons accumulate — an element is routinely both unreachable and
  /// clipped — and `blocked` orders explanations ahead of the observation.
  public enum Reason: Sendable, Equatable {
    /// The accessibility server can name no point at which a touch reaches this element, and has not
    /// said why: `IsVisible == false` read straight through.
    ///
    /// Covers several situations only a hit-test can separate — a label inside a tappable control, a
    /// pass-through container, an element genuinely covered by an unrelated one, and one transparent
    /// or clipped by an ancestor. Because it explains nothing it sorts last in `reasons`.
    case notHittable
    /// The element has a reachable point, but it is not the centre — so the centre is covered, and
    /// automation aiming there hits whatever is on top. `by` names that element when a hit-test was paid
    /// for, and is nil otherwise.
    case occluded(by: FBAccessibilityElementRef?)
    /// A touch aimed here is delivered to a relative instead — an ancestor that owns this element, or a
    /// descendant it passes through to. The element is not independently interactive and was never meant
    /// to be: a label inside a button, or a container laying out the control that does the work.
    ///
    /// Not a fault, and the recovery is neither scrolling nor moving anything: act on the named element.
    /// Requires a hit-test, so it appears only when `occludedBy` was requested — without it these fall
    /// back to plain `notHittable`.
    case handledBy(FBAccessibilityElementRef?)
    /// The view has `userInteractionEnabled` off.
    case userInteractionDisabled
    /// The element reports itself disabled.
    case disabled
    /// The element declares itself hidden from accessibility.
    case hidden
    /// The element has no area to tap.
    case zeroSize
    /// Part of the element's frame lies outside the screen. The recovery is to bring the element fully
    /// into view and try again.
    ///
    /// Never reported by the server; computed from plain geometry against the screen bounds the
    /// document carries. Accumulates alongside other reasons — clipped and covered are not
    /// alternatives, and an element is often both.
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

  /// Nil when either coordinate is non-finite, as `FBAccessibilityFrame` normalizes its edges.
  public init?(_ point: CGPoint) {
    guard point.x.isFinite, point.y.isFinite else {
      return nil
    }
    self.init(x: Double(point.x), y: Double(point.y))
  }
}

/// An element resolved by a hit-test — whatever actually receives a touch aimed at another element.
///
/// Descriptive rather than a handle: a hit-test resolves an element with no identity that outlives the
/// call. Used both for an unrelated element covering the target and for a relative of the target that
/// takes the touch on its behalf.
public struct FBAccessibilityElementRef: Sendable, Equatable, Encodable {
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

public extension FBAccessibilityInteractable.Reason {
  /// Whether this reason merely observes that the element is unreachable, without explaining it.
  var isUnexplained: Bool {
    if case .notHittable = self { return true }
    return false
  }
}

public extension Array where Element == FBAccessibilityInteractable.Reason {
  /// The reasons with every explaining reason ahead of `notHittable`, each group keeping the order it
  /// was derived in.
  ///
  /// A partition rather than a sort: Swift's sort is not guaranteed stable, and the derivation order
  /// within a group is meaningful — it is the order the checks run in, which the tests pin.
  var mostSpecificFirst: [FBAccessibilityInteractable.Reason] {
    filter { !$0.isUnexplained } + filter { $0.isUnexplained }
  }
}

public extension FBAccessibilityInteractable {

  /// The union is **internally tagged**: every value is an object and the shapes differ by case, so a
  /// consumer discriminates on `status` rather than probing for which key happens to be present.
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
      // Ordered here rather than trusting every construction site: the guarantee that `reasons[0]` is the
      // most actionable thing known belongs to the wire, and a refinement pass that returns early must not
      // be able to bypass it.
      try container.encode(reasons.mostSpecificFirst, forKey: .reasons)
    }
  }
}

extension FBAccessibilityInteractable.Reason: Encodable {

  enum CodingKeys: String, CodingKey {
    case kind
    case by
  }

  /// The wire spelling of each reason. Pinned by test — these are the tokens a consumer branches on.
  public var kind: String {
    switch self {
    case .notHittable: return "not_hittable"
    case .occluded: return "occluded"
    case .handledBy: return "handled_by"
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
    // `by` is emitted only by the cases that can have one, and only when a hit-test named it — the reason
    // the reference lives on the case rather than beside it.
    switch self {
    case let .occluded(by), let .handledBy(by):
      try container.encodeIfPresent(by, forKey: .by)
    default:
      break
    }
  }
}

/// How well this read could explain the elements it found blocked.
///
/// `unexplained` counts elements whose only reason is the bare `notHittable` observation. An element
/// nothing explains is still reported as blocked: a caller acting on it needs to know it cannot act,
/// whether or not the reason is known.
public struct FBAccessibilityInteractionSummary: Sendable, Equatable, Encodable {

  /// Elements reported actionable.
  public let actionable: Int
  /// Elements reported blocked, for any reason.
  public let blocked: Int
  /// Of those, the ones carrying only `notHittable` — blocked with nothing that explains it.
  public let unexplained: Int
  /// `unexplained / blocked`, or nil when nothing was blocked.
  public let unexplainedRatio: Double?

  public init(actionable: Int, blocked: Int, unexplained: Int) {
    self.actionable = actionable
    self.blocked = blocked
    self.unexplained = unexplained
    self.unexplainedRatio = blocked > 0 ? Double(unexplained) / Double(blocked) : nil
  }

  /// Tallies a serialized read, or nil when no element carried a verdict at all.
  ///
  /// Nil rather than zeroes, because "not requested" and "requested, and the backend could not answer"
  /// must not read as "a screen with nothing blocked". A legacy-backend read, where every verdict is
  /// null, reports nothing here rather than 0 unexplained.
  public init?(elements: [FBAccessibilityDocumentElement]) {
    var actionable = 0
    var blocked = 0
    var unexplained = 0
    func visit(_ element: FBAccessibilityDocumentElement) {
      switch element.interactable ?? nil {
      case .actionable:
        actionable += 1
      case let .blocked(reasons):
        blocked += 1
        if reasons.allSatisfy(\.isUnexplained) {
          unexplained += 1
        }
      case nil:
        break
      }
      for child in element.children ?? [] {
        visit(child)
      }
    }
    for element in elements {
      visit(element)
    }
    guard actionable > 0 || blocked > 0 else {
      return nil
    }
    self.init(actionable: actionable, blocked: blocked, unexplained: unexplained)
  }

  enum CodingKeys: String, CodingKey {
    case actionable
    case blocked
    case unexplained
    case unexplainedRatio = "unexplained_ratio"
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(actionable, forKey: .actionable)
    try container.encode(blocked, forKey: .blocked)
    try container.encode(unexplained, forKey: .unexplained)
    try container.encode(unexplainedRatio, forKey: .unexplainedRatio)
  }
}

/// How many of a read's elements carry a usable rectangle.
///
/// A view out of its window reports `CGRectZero` while keeping its label, so geometry is the one
/// attribute that degrades when the tree does; the framed-to-zero-framed split within one read is the
/// signal. Raw counts, no ratio and no verdict: what proportion is suspicious depends on the screen —
/// a scrolled-away list legitimately contributes zero-framed elements — so the threshold belongs to
/// the consumer.
///
/// `total` counts elements carrying a `frame` attribute, not "things on screen": a single visible row
/// routinely contributes several framed elements.
///
/// `nil` when the read did not carry `frame` at all. Nil rather than zeroes, as in
/// `FBAccessibilityInteractionSummary`: "not requested" must not read as "every element is framed".
public struct FBAccessibilityFrameSummary: Sendable, Equatable, Encodable {

  /// Elements carrying a `frame` attribute, whatever its value.
  public let total: Int
  /// Of those, the ones with a positive-area rectangle.
  public let framed: Int
  /// Of those, the ones whose rectangle has no area, or whose edges were not representable.
  public let zeroFrame: Int

  public init(total: Int, framed: Int, zeroFrame: Int) {
    self.total = total
    self.framed = framed
    self.zeroFrame = zeroFrame
  }

  /// Tallies a serialized read, or nil when no element carried a frame.
  public init?(elements: [FBAccessibilityDocumentElement]) {
    var total = 0
    var framed = 0
    func visit(_ element: FBAccessibilityDocumentElement) {
      if let frame = element.frame {
        total += 1
        // Counts as framed only with area on both axes; a frame with a missing edge (`rect == nil`)
        // falls to the zero-frame side rather than being dropped from the tally.
        if let rect = frame?.rect, rect.width > 0, rect.height > 0 {
          framed += 1
        }
      }
      for child in element.children ?? [] {
        visit(child)
      }
    }
    for element in elements {
      visit(element)
    }
    guard total > 0 else {
      return nil
    }
    self.init(total: total, framed: framed, zeroFrame: total - framed)
  }

  enum CodingKeys: String, CodingKey {
    case total
    case framed
    case zeroFrame = "zero_frame"
  }
}

/// Where a guest-backed read spent its time.
///
/// A separate type from `FBAccessibilityProfilingData` because the two backends measure disjoint
/// phases; the document's `backend` field says which shape a consumer is holding.
///
/// The first five fields are the core, spelled identically in both profiles so the lanes stay
/// comparable.
public struct FBAXBridgeProfile: Sendable, Equatable, Encodable {

  // MARK: The core, spelled identically in every backend's profile

  /// Elements in the serialized read.
  public let elementCount: Int64
  /// Wall time for the whole read, host-side.
  public let totalDuration: CFAbsoluteTime
  /// Everything the round trip was not the guest's walk: getting a usable guest, the guest's own JSON
  /// encoding, and the IPC. A **residual**, not a measurement — neither side can separate the three.
  public let acquireDuration: CFAbsoluteTime
  /// Pulling the tree out of the application.
  public let readDuration: CFAbsoluteTime
  /// Turning what was read into what the caller asked for.
  public let serializeDuration: CFAbsoluteTime

  // MARK: What only a guest-backed read has

  /// The traversal that produced this read. Without it `machRoundTrips` is ambiguous: the same tree
  /// costs one round trip or one per node depending on the traversal.
  ///
  /// Guest-only rather than part of the core, because the `testmanagerd` backend has no traversal to
  /// report.
  public let traversal: FBAXTraversal

  /// Round trips to the application's accessibility server — one per node.
  public let machRoundTrips: Int64?
  /// Host-side decode of the guest's JSON response.
  public let hostDecodeDuration: CFAbsoluteTime?
  /// Response size.
  public let responseBytes: Int64?

  public init(
    elementCount: Int64,
    totalDuration: CFAbsoluteTime,
    acquireDuration: CFAbsoluteTime,
    readDuration: CFAbsoluteTime,
    serializeDuration: CFAbsoluteTime,
    traversal: FBAXTraversal,
    machRoundTrips: Int64? = nil,
    hostDecodeDuration: CFAbsoluteTime? = nil,
    responseBytes: Int64? = nil
  ) {
    self.elementCount = elementCount
    self.totalDuration = totalDuration
    self.acquireDuration = acquireDuration
    self.readDuration = readDuration
    self.serializeDuration = serializeDuration
    self.traversal = traversal
    self.machRoundTrips = machRoundTrips
    self.hostDecodeDuration = hostDecodeDuration
    self.responseBytes = responseBytes
  }

  enum CodingKeys: String, CodingKey {
    case elementCount = "element_count"
    case totalDurationMs = "total_duration_ms"
    case acquireDurationMs = "acquire_duration_ms"
    case readDurationMs = "read_duration_ms"
    case serializeDurationMs = "serialize_duration_ms"
    case traversal
    case machRoundTrips = "mach_round_trips"
    case hostDecodeDurationMs = "host_decode_duration_ms"
    case responseBytes = "response_bytes"
  }

  /// Durations are emitted in milliseconds, matching the translator profile. A phase that does not apply
  /// to this transport keeps its key with a null value rather than vanishing — absent would mean "this
  /// build does not report it", and nil here means "this transport does not have this phase".
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(elementCount, forKey: .elementCount)
    try container.encode(totalDuration * 1000, forKey: .totalDurationMs)
    try container.encode(acquireDuration * 1000, forKey: .acquireDurationMs)
    try container.encode(readDuration * 1000, forKey: .readDurationMs)
    try container.encode(serializeDuration * 1000, forKey: .serializeDurationMs)
    try container.encode(traversal.rawValue, forKey: .traversal)
    try container.encode(machRoundTrips, forKey: .machRoundTrips)
    try container.encode(hostDecodeDuration.map { $0 * 1000 }, forKey: .hostDecodeDurationMs)
    try container.encode(responseBytes, forKey: .responseBytes)
  }
}

/// Which backend's profile a document carries.
///
/// A Swift-level sum so the two disjoint types can share one slot; **not** a tagged union on the wire.
/// It encodes transparently — the emitted JSON is exactly one struct's fields with no discriminator
/// wrapping them; the document's `backend` field is the discriminator.
public enum FBAccessibilityProfile: Sendable, Equatable, Encodable {
  case translator(FBAccessibilityProfilingData)
  case guestBridge(FBAXBridgeProfile)

  /// The translator profile, or nil on a guest-backed read.
  public var translatorProfile: FBAccessibilityProfilingData? {
    guard case let .translator(profile) = self else {
      return nil
    }
    return profile
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .translator(profile):
      try container.encode(profile)
    case let .guestBridge(profile):
      try container.encode(profile)
    }
  }
}

/// What narrowed a read, and how much of it survived.
///
/// A caller that asked for `--match Cart` and got back three elements cannot otherwise tell that from
/// a screen with three elements on it: the narrowing happens on the companion, and the document that
/// comes back looks the same either way. This says what the read applied and what it dropped, so an
/// empty result reads as "the substring matched nothing out of 812" rather than as "the read failed".
///
/// Emitted on every `complete` document, including reads that narrowed nothing — those report the
/// default filter, a null match, and equal counts. A consumer therefore never has to distinguish "did
/// not narrow" from "the companion predates this field" by whether a key is present.
public struct FBAccessibilityNarrowing: Sendable, Equatable, Encodable {

  /// The substring the read reported only the matching elements for, or nil when it did not narrow by
  /// one. A marker read leaves this null: it reports its search through `target`, not here.
  public let match: String?

  /// The element key `match` was compared against, and whether that comparison ignored case. Both null
  /// when there was no match — they describe a comparison that did not happen, and reporting a default
  /// for it would read as one that did.
  public let matchKey: String?
  public let ignoreCase: Bool?

  /// The element filter the read applied, spelled as the CLI spells it.
  public let filter: String

  /// Elements walked before narrowing, and elements reported after it. Counted through `children`, so
  /// the pair means the same thing for a nested read as for a flat one, and equal when nothing
  /// narrowed.
  public let walked: Int
  public let matched: Int

  public init(match: String?, matchKey: String?, ignoreCase: Bool?, filter: String, walked: Int, matched: Int) {
    self.match = match
    self.matchKey = matchKey
    self.ignoreCase = ignoreCase
    self.filter = filter
    self.walked = walked
    self.matched = matched
  }

  enum CodingKeys: String, CodingKey {
    case match
    case matchKey = "match_key"
    case ignoreCase = "ignore_case"
    case filter
    case walked
    case matched
  }

  // `encode` rather than `encodeIfPresent`: the document's key set is fixed, so a match that was not
  // asked for is an explicit `null` rather than an absent key.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(match, forKey: .match)
    try container.encode(matchKey, forKey: .matchKey)
    try container.encode(ignoreCase, forKey: .ignoreCase)
    try container.encode(filter, forKey: .filter)
    try container.encode(walked, forKey: .walked)
    try container.encode(matched, forKey: .matched)
  }
}

public extension FBAccessibilityNarrowing {
  /// The report for a read that applied `filter` and `match`, walking `walked` nodes and reporting
  /// `matched` of them.
  ///
  /// Spelled from the typed filter and match rather than from strings at the call site, so the echo
  /// cannot claim a narrowing the read did not apply; the counts are all the site contributes.
  init(filter: FBAccessibilityElementFilter, match: FBAccessibilityMatch?, walked: Int, matched: Int) {
    self.init(
      match: match?.value,
      matchKey: match?.key.rawValue,
      ignoreCase: match.map(\.ignoresCase),
      filter: filter.rawValue,
      walked: walked,
      matched: matched)
  }

  /// The report for a read that hit-tested remote content in addition to walking the element tree.
  ///
  /// The discovered elements were walked too, and were narrowed by the same `filter` and `match`, so
  /// they belong on both sides of the count: `discovered` adds to `walked`, and whatever survived
  /// narrowing is already counted in `reported`. Pairing the counts here — rather than by hand at the
  /// call site — is what stops a read that reported matching remote content from claiming more matched
  /// than it walked.
  init(
    filter: FBAccessibilityElementFilter,
    match: FBAccessibilityMatch?,
    walked: [FBAccessibilityDocumentElement],
    discovered: [FBAccessibilityDocumentElement],
    reported: [FBAccessibilityDocumentElement]
  ) {
    self.init(
      filter: filter, match: match,
      walked: walked.nodeCount + discovered.nodeCount, matched: reported.nodeCount)
  }
}

public extension FBAccessibilityRequestOptions {
  /// The narrowing report for a read under these options that walked `walked` and reported `reported`.
  func narrowingReport(
    walked: [FBAccessibilityDocumentElement], reported: [FBAccessibilityDocumentElement]
  ) -> FBAccessibilityNarrowing {
    FBAccessibilityNarrowing(
      filter: filter, match: match, walked: walked.nodeCount, matched: reported.nodeCount)
  }
}

public extension [FBAccessibilityDocumentElement] {
  /// Elements in a serialized read, counted through `children`.
  ///
  /// The nested formats put a single root at the top level, so `count` would report 1 for any tree.
  var nodeCount: Int {
    reduce(0) { $0 + 1 + ($1.children ?? []).nodeCount }
  }
}

/// The device's accessibility automation mode as it stood for a read, and whether the read changed it.
///
/// Reported on every whole-tree read: with the mode off UIKit collapses subtrees behind opaque element
/// providers and caches a container's children; with it on the full structure is exposed and children
/// are recomputed per read. `asserted` distinguishes a read that changed the device setting from one
/// that found it already set.
public struct FBAccessibilityAutomationState: Sendable, Equatable, Encodable {

  /// Whether the device was in automation mode for this read.
  public let enabled: Bool
  /// Whether this read put it there. False when it was already set, or when nothing asked.
  public let asserted: Bool

  public init(enabled: Bool, asserted: Bool) {
    self.enabled = enabled
    self.asserted = asserted
  }

  enum CodingKeys: String, CodingKey {
    case enabled
    case asserted
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
  /// this is derived from, and the explicit null keeps the key set fixed across backends.
  public var interactable: FBAccessibilityInteractable??
  public var customActions: [String]??
  public var traits: [String]??
  public var pid: Int64??
  /// The raw role (`AXButton`) and the stringified frame. `complete` reports these through `type` and
  /// `frame` instead, so they are absent from its `CodingKeys` — they exist for the legacy spelling,
  /// which emits both.
  public var role: String??
  public var axFrame: String??
  /// What a hit-test at this element's centre found, as the backend reported it.
  ///
  /// Not part of the emitted schema and absent from `CodingKeys`: it is an *input* to deciding why an
  /// element is blocked, consumed by the refinement that turns it into a reason and never emitted on
  /// its own. Carried on the element so the guest answers once, inline with the tree.
  public var explainedBy: FBAccessibilityElementRef?
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
  public let profile: FBAccessibilityProfile?
  public let coverage: FBAccessibilityCoverage?
  /// How much of what this read found blocked it could explain. Nil when `interactable` was not
  /// requested, since there is then nothing to summarize.
  public let interaction: FBAccessibilityInteractionSummary?
  /// How many of the read's elements carry a usable rectangle. Nil when `frame` was not requested.
  public let frames: FBAccessibilityFrameSummary?
  /// The device's accessibility automation mode for this read. Nil when the backend cannot report it —
  /// a single-element read, or a guest predating the field.
  public let automation: FBAccessibilityAutomationState?
  /// What the read was narrowed by and how much survived. Nil for a single-element read, which selects
  /// rather than narrows.
  public let narrowing: FBAccessibilityNarrowing?

  public init(
    elements: [FBAccessibilityDocumentElement],
    modal: FBAccessibilityModalInfo? = nil,
    truncated: Bool = false,
    screen: FBAccessibilityScreenInfo? = nil,
    backend: FBUIAutomationBackendName? = nil,
    target: FBAccessibilityTargetDescriptor? = nil,
    profile: FBAccessibilityProfile? = nil,
    coverage: FBAccessibilityCoverage? = nil,
    interaction: FBAccessibilityInteractionSummary? = nil,
    frames: FBAccessibilityFrameSummary? = nil,
    automation: FBAccessibilityAutomationState? = nil,
    narrowing: FBAccessibilityNarrowing? = nil
  ) {
    self.elements = elements
    self.modal = modal
    self.truncated = truncated
    self.screen = screen
    self.backend = backend
    self.target = target
    self.profile = profile
    self.coverage = coverage
    self.interaction = interaction
    self.frames = frames
    self.automation = automation
    self.narrowing = narrowing
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
    case interaction
    case frames
    case automation
    case narrowing
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
    try container.encode(interaction, forKey: .interaction)
    try container.encode(frames, forKey: .frames)
    try container.encode(automation, forKey: .automation)
    try container.encode(narrowing, forKey: .narrowing)
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
  /// Rendered by hand for `JSONSerialization` — see `FBAccessibilityElementPayload.legacyFoundationObject`.
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
