/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreFoundation
import CoreGraphics
import Darwin
import Foundation

#if canImport(SimulatorFrameworkBridgeRuntime)
@_implementationOnly import SimulatorFrameworkBridgeRuntime
#endif

// The `XC_kAXXC*` attribute keys. These MUST match `AXWire.Node` host-side so the emitted tree feeds
// the shared serializer (via `AXBridgePlatformElement`) unchanged.
private let axElementType = "XC_kAXXCAttributeElementType"
private let axElementBaseType = "XC_kAXXCAttributeElementBaseType"
private let axLabel = "XC_kAXXCAttributeLabel"
private let axValue = "XC_kAXXCAttributeValue"
private let axIdentifier = "XC_kAXXCAttributeIdentifier"
private let axFrame = "XC_kAXXCAttributeFrame"
private let axAutomationType = "XC_kAXXCAttributeAutomationType"
private let axChildren = "XC_kAXXCAttributeChildren"
// Both answered as CGPoint. `VisiblePoint` reads `(-1, -1)` when the server believes no touch reaches the
// element; carried verbatim, sentinel included — deciding what unreachable means is the host's job.
private let axVisiblePoint = "XC_kAXXCAttributeVisiblePoint"
private let axCenterPoint = "XC_kAXXCAttributeCenterPoint"
// Whether the server can name a point at which a touch reaches the element; the walk uses it to pick
// nodes worth explaining.
private let axisVisible = "XC_kAXXCAttributeIsVisible"
private let requestVerb = "verb"
private let requestPid = "pid"
private let requestMaxDepth = "maxDepth"
private let requestMaxNodes = "maxNodes"
// The attributes fetched per element. Optional: absent means `FBAXBridgeDefaultFetchList()`. Named per
// request so an attribute nobody asked for stays off the wire entirely.
private let requestAttributes = "attributes"
// Whether this read wants the device in accessibility automation mode. Tri-state on purpose: **absent**
// means observe and report without touching the device, which is what a host that does not know about
// this field gets; `true` and `false` each assert that state. Absent and `false` are not the same thing —
// one leaves the device alone and the other actively turns the mode off.
private let requestAutomationMode = "automationMode"
// Asks the walk to explain each element the accessibility server reports unreachable, by hit-testing that
// element's centre and reporting whatever answered. Optional and off by default: it costs an extra AX
// round trip per unreachable element, and only a caller that intends to use the answer should pay.
private let requestExplainUnreachable = "explainUnreachable"
// Reads through the translator's vocabulary instead of XCTest's. Off by default; the two disagree on
// some screens.
private let requestTranslatorVocabulary = "translatorVocabulary"
// Reads the whole subtree in one call, through `userTestingSnapshotForElement:options:error:`, instead
// of one call per node. Selected by the host's `single-fetch` traversal; the per-node walk is still the
// default.
private let requestSnapshotTree = "snapshotTree"
// Reader-derived keys (below) are spelled in the reader's own namespace, not `XC_kAXXC*`, so the two
// kinds stay distinguishable on the wire.
private let nodeExplainedBy = "FBExplainedBy"
// The translator's own `enabled` answer; XCTest's vocabulary has no counterpart. Only a translator read
// carries this.
private let nodeIsEnabled = "FBIsEnabled"
// The translator's `role`, carried as its raw integer for the host to map. Not folded into `elementType`,
// which carries `XCUIElementType` names.
private let nodeTranslatorRole = "FBTranslatorRole"
// The translator's `subrole`, as its raw integer; it refines the role rather than replacing it.
private let nodeTranslatorSubrole = "FBTranslatorSubrole"
// The `UIAccessibilityTraits` bitmask, carried raw. Decoding it needs the trait constants, which live in
// a macOS-only header this binary cannot import — so the number rides the wire and the host names it.
private let nodeTraits = "FBTraits"
// A per-element identity from the translator, so two reads can be compared element by element.
private let nodeElementIdentity = "FBElementIdentity"
// Present only on a node where at least one attribute failed to read, mapping the attribute's key to the
// reason.
private let nodeAttributeReadFailures = "FBAttributeReadFailures"
// Echoed back by the shutdown verb so a caller can tell an honoured shutdown from an ok-shaped response
// to something else.
private let responseShutdown = "shutdown"
private let requestX = "x"
private let requestY = "y"
// Selects how a fused frontmost read (a `describe` with no pid) resolves the foreground app. Optional;
// defaults to `window-server` (the authoritative query).
private let requestMethod = "method"
// The semantic action a `perform` asks for, and the string a `setvalue` writes.
private let requestAction = "action"
private let requestValue = "value"
// Device-wide accessibility setting name and requested state.
private let requestSetting = "setting"
private let requestEnabled = "enabled"
// What the element at the point must still be for the write to go ahead: one node attribute key and the
// value it has to equal. Optional, and only meaningful together.
private let requestAssertKey = "assertKey"
private let requestAssertValue = "assertValue"
private let responseOk = "ok"
private let responseEnabled = "enabled"
private let responseTree = "tree"
private let responseError = "error"
// A successful hit-test that found no element at the point: `{ok:true, empty:true}` — distinct from a
// reader failure (`{ok:false, error:...}`), so the host can tell empty space from a broken reader.
private let responseEmpty = "empty"
// A closed-vocabulary failure kind, so the host picks a remedy structurally rather than by matching the
// free-text `error`. Absent kind = plain reader failure; a host must treat an unknown kind the same way,
// so adding a value here degrades an older host's precision rather than breaking it.
private let responseErrorKind = "error_kind"
// The named process has no accessibility server: a dead pid, or a process that is not an application.
private let errorKindApplicationUnavailable = "application_unavailable"
// The named process has one and it did not answer in time — alive but busy, suspended or wedged.
private let errorKindApplicationNotResponding = "application_not_responding"
// The selected frontmost strategy could not name an application, for a reason that is about the strategy
// rather than about any one application.
private let errorKindFrontmostUnresolved = "frontmost_unresolved"
// The reader could not bind the private frameworks it reads through, so no request can be served. The
// `error` names what was missing and what else about the runtime has moved.
private let errorKindReaderUnavailable = "reader_unavailable"
// The request itself was malformed — an unknown verb, or a missing or wrongly-typed argument.
private let errorKindBadRequest = "bad_request"
// A write was refused before it was attempted: the element found at the point is not the one the caller
// named. Held apart from `bad_request` because the request was well-formed — the screen moved.
private let errorKindAssertionFailed = "assertion_failed"
// A whole-tree read whose walk was cut short by the depth cap or the node budget: the returned tree is
// a partial view, so the host can warn rather than pass it off as complete. Absent or `false` means the
// walk visited every element within the bounds.
private let responseTruncated = "truncated"
// The resolved foreground pid and the mechanism that resolved it. The pid also tags the owning element
// of a hit-test result.
private let responsePid = "pid"
private let responseMethod = "method"
// The automation mode this read ran under, and whether this read changed it. Reported on every describe:
// a tree read with subtree collapsing on is a different answer from the same tree read with it off.
private let responseAutomation = "automation"
// Where the guest spent its time and how many round trips it took. Reported on every describe (a handful
// of clock reads). Guest-side JSON encoding is not included — it falls into the host's residual.
private let responsePhases = "phases"
private let phaseTraverse = "traverse_ms"
private let phaseMachRoundTrips = "mach_round_trips"
private let kAutomationEnabled = "enabled"
private let kAutomationAsserted = "asserted"
// A fullscreen modal/alert descriptor added to a describe response when one is detected in the tree.
// Host-facing enrichment on the wire; the host does not put it in the serialized CLI output.
private let responseModal = "modal"
private let modalKind = "kind"
private let modalKindSystem = "system"
private let modalKindApp = "app"
private let modalElementType = "elementType"
private let modalLabel = "label"
// Concrete accessibility element classes that mark a modal: a SpringBoard system alert window, and the
// UIKit alert controller view (matched by prefix — the concrete class varies by idiom/OS).
private let systemAlertWindowClass = "SBAlertItemWindow"
private let alertControllerClassPrefix = "_UIAlertController"
private let verbDescribe = "describe"
private let verbHitTest = "hittest"
// Asks a `serve` process to exit; answered before exiting so the caller learns it was honoured. The serve
// loop holds one client at a time, so any answer proves the caller is the only client — being answered is
// how a host learns a bridge is free.
private let verbShutdown = "shutdown"
private let verbPerform = "perform"
private let verbSetValue = "setvalue"
private let verbGetDeviceSetting = "settings-get"
private let verbSetDeviceSetting = "settings-set"
private let actionServe = "serve"
// The semantic actions a `perform` request can name — the wire spelling of `FBAXAction`, which is what the
// host sends and what the guest maps back. Unrelated to `kActionServe`, which is an argv sub-command.
private let actionPress = "press"
private let actionScrollUp = "scroll-up"
private let actionScrollDown = "scroll-down"
private let actionScrollLeft = "scroll-left"
private let actionScrollRight = "scroll-right"
private let actionScrollToVisible = "scroll-to-visible"
// The frontmost-resolution methods, shared by the request `method` selector and the response `method`
// value: a request selects a strategy with one of these, and a fused frontmost response echoes back the
// one that answered, so a guest-reported `method` round-trips into the host's `AXBridgeFrontmostMethod`.
// `center-point` is the positional system-wide hit-test; `window-server` is the authoritative query, and
// the default when a request names no method.
private let methodCenterPoint = "center-point"
private let methodWindowServer = "window-server"
private let methodRunningBoard = "runningboard"
// A depth cap and a total-node budget guard against pathological trees. A request carries the
// caller's own bounds (the host sets them so every backend truncates alike); these apply only when it
// does not — e.g. the one-shot front-end invoked by hand.
private let defaultMaxDepth = 100
private let defaultNodeBudget = 5000
private final class AccessibilityRequest {
  // MARK: - AX client setup

  // Kept short: read once per unreachable element.
  fileprivate func FBAXBridgeExplanationFetchList() -> [String] {
    [axElementType, axLabel, axIdentifier, axFrame, axAutomationType]
  }

  // The attributes a read fetches when the request names none. Membership *and* order are part of the wire
  // contract, mirrored host-side by `AXWire.Node.defaultFetchList`.
  fileprivate func FBAXBridgeDefaultFetchList() -> [String] {
    [axElementType, axElementBaseType, axLabel, axValue, axIdentifier, axFrame, axAutomationType, axChildren]
  }

  // Names are forwarded unfiltered — the vocabulary is far wider than the constants here. The children key
  // is always appended: the walk recurses on it, and omitting it would flatten the tree to its root.
  //
  // Hazard: the framework drops any name it has no number for, then fails the whole read on the count
  // mismatch — one unknown key costs every attribute for that node, not just itself.
  fileprivate func FBAXBridgeFetchListForRequest(request: [String: Any]) -> [String] {
    let requested = request[requestAttributes]
    guard let requested = requested as? [Any] else {
      return FBAXBridgeDefaultFetchList()
    }
    var attributes: [String] = []
    for name in requested {
      if let name = name as? String {
        attributes.append(name)
      }
    }
    if attributes.isEmpty {
      return FBAXBridgeDefaultFetchList()
    }
    if !attributes.contains(axChildren) {
      attributes.append(axChildren)
    }
    return attributes
  }

  // Counted rather than inferred from node count, which would undercount by up to 2x (the translator walk
  // makes two requests per node; explaining an unreachable element adds two more).
  private var gRoundTrips: Int64 = 0
  fileprivate func FBAXBridgeCountRoundTrip() {
    gRoundTrips += 1
  }

  // An outcome whose status and payload disagree. Unreachable through the factories; reported as a response
  // rather than raised because the guest serves a long-lived connection.
  fileprivate func FBAXBridgeInvariantError(description: String) -> Error {
    NSError(domain: "FBAXBridgeInvariant", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
  }

  // MARK: - JSON coercion

  // A geometry value none of a coercion's branches recognises. Answered as null — the same answer a
  // missing attribute gets — never as a zeroed dictionary, which is well-formed geometry at the screen
  // origin and indistinguishable from a real answer.
  fileprivate func FBAXBridgeRejectedGeometry(kind: String, value: Any) -> Any {
    NSLog("[AccessibilityService] unexpected %@ value class: %@", kind, String(describing: type(of: value)))
    return NSNull()
  }

  // The frame arrives from `attributesForElement:` as an `NSValue`-wrapped `CGRect` (or, tolerantly, an
  // existing dictionary representation). Emit the CGRect dictionary representation the host consumes via
  // `CGRectMakeWithDictionaryRepresentation`.
  fileprivate func FBAXBridgeFrameDictionary(
    client: FBAXClient,
    frameValue: Any
  ) throws -> Any? {
    var rect: CGRect = .zero
    if let frameValue = frameValue as? NSDictionary {
      guard try client.isValidRectangle(frameValue).boolValue else {
        return FBAXBridgeRejectedGeometry(kind: "frame", value: frameValue)
      }
      return frameValue
    }
    let result = try client.rectangle(fromValue: frameValue)
    guard let geometry = result.value else {
      return FBAXBridgeRejectedGeometry(kind: "frame", value: frameValue)
    }
    geometry.getValue(&rect, size: MemoryLayout.size(ofValue: rect))
    return CGRectCreateDictionaryRepresentation(rect) as NSDictionary
  }

  // Keyed on the attribute name, as the frame is, so a value that merely looks like an X/Y pair is never
  // reinterpreted as a coordinate.
  fileprivate func FBAXBridgeIsPointAttribute(key: String) -> Bool {
    key == axVisiblePoint || key == axCenterPoint
  }

  // Emit the `CGPoint` dictionary representation the host consumes, as the frame's coercion does. Rejection
  // matters more here than for the frame: the host taps these points and `{0,0}` is a plausible target.
  fileprivate func FBAXBridgePointDictionary(
    client: FBAXClient,
    pointValue: Any
  ) throws -> Any? {
    var point: CGPoint = .zero
    if let pointValue = pointValue as? NSDictionary {
      guard try client.isValidPoint(pointValue).boolValue else {
        return FBAXBridgeRejectedGeometry(kind: "point", value: pointValue)
      }
      return pointValue
    }
    let result = try client.point(fromValue: pointValue)
    guard let geometry = result.value else {
      return FBAXBridgeRejectedGeometry(kind: "point", value: pointValue)
    }
    geometry.getValue(&point, size: MemoryLayout.size(ofValue: point))
    return CGPointCreateDictionaryRepresentation(point) as NSDictionary
  }

  // Coerce an attribute value to a JSON-serializable form. Strings and numbers pass through; the frame
  // becomes a dictionary; anything else is stringified so the payload never fails serialization.
  fileprivate func FBAXBridgeJSONSafeValue(
    client: FBAXClient,
    value: Any?,
    key: String
  ) throws -> Any? {
    guard let value, !(value is NSNull) else {
      return NSNull()
    }
    if key == axFrame {
      return try FBAXBridgeFrameDictionary(client: client, frameValue: value)
    }
    if FBAXBridgeIsPointAttribute(key: key) {
      return try FBAXBridgePointDictionary(client: client, pointValue: value)
    }
    if value is String || value is NSNumber {
      return value
    }
    // The framework reports a failed attribute by returning the error in place of the value, so an error
    // arrives in the same shape as an answer. Stringifying it would describe the element as having that
    // string as the attribute — a label of "Error Domain=..." reads as a real label to anything matching on
    // one. Absent a value, the honest answer is that there is none; `kNodeAttributeReadFailures` carries
    // which keys failed and why.
    guard value is NSError else {
      return try client.description(ofValue: value).value
    }
    return NSNull()
  }

  // MARK: - Tree walk

  // Whether the accessibility server said this node is reachable. Absent or non-boolean counts as
  // reachable, so an explanation is never attempted for a node the caller did not ask visibility about.
  fileprivate func FBAXBridgeNodeIsUnreachable(node: [String: Any]) throws -> Bool {
    guard let visible = node[axisVisible] as? NSNumber else {
      return false
    }
    return try !FBAXWireValue.boolean(from: visible).boolValue
  }

  // The element a display-wide hit-test finds at `point`, described by the explanation fetch list, or nil.
  // Display-wide on purpose: an element covered by another process's chrome is covered whoever drew it.
  fileprivate func FBAXBridgeExplanationAtPoint(
    client: FBAXClient,
    point: CGPoint
  ) throws -> [String: Any]? {
    FBAXBridgeCountRoundTrip()
    let hit = try client.hitTest(at: point, processIdentifier: 0)
    if hit.status != FBAXHitTestStatus.hit {
      return nil
    }
    let hitElement = hit.element
    guard let hitElement else {
      return nil
    }
    FBAXBridgeCountRoundTrip()
    let read = try client.readAttributes(FBAXBridgeExplanationFetchList(), of: hitElement)
    guard read.status == FBAXReadStatus.read, let attributes = read.attributes else {
      return nil
    }
    var explanation = [String: Any]()
    for key in attributes.keys {
      explanation[key] = try FBAXBridgeJSONSafeValue(
        client: client,
        value: attributes[key],
        key: key
      )
    }
    return explanation
  }

  // Read from the node rather than derived from the frame, so it matches what the server measured
  // reachability against.
  fileprivate func FBAXBridgeNodeCentre(client: FBAXClient, node: [String: Any], point: inout CGPoint) throws -> Bool {
    let centre = node[axCenterPoint]
    guard let centre = centre as? NSDictionary else {
      return false
    }
    guard let geometry = try client.point(fromValue: centre).value else {
      return false
    }
    geometry.getValue(&point, size: MemoryLayout.size(ofValue: point))
    return true
  }

  // One mach round-trip per node: read the element's attributes, coerce them to JSON, then recurse into
  // its children (replacing the child `XCAccessibilityElement`s with their read dictionaries in place).
  //
  // The outcome describes only *this* element. A child that fails to read is dropped from the tree rather
  // than failing the whole read, so a child's outcome never becomes the caller's.
  fileprivate func FBAXBridgeBuildNode(
    client: FBAXClient,
    element: FBAXElement,
    fetchList: [String],
    explainUnreachable: Bool,
    depth: Int,
    maxDepth: Int,
    budget: inout Int,
    truncated: inout Bool
  ) throws -> FBAXReadOutcome {
    FBAXBridgeCountRoundTrip()
    let outcome = try client.readAttributes(fetchList, of: element)
    switch outcome.status {
    case FBAXReadStatus.applicationUnavailable:
      return FBAXReadOutcome.applicationUnavailable()
    case FBAXReadStatus.applicationNotResponding:
      return FBAXReadOutcome.applicationNotResponding()
    case FBAXReadStatus.read:
      break
    case FBAXReadStatus.failed:
      fallthrough
    @unknown default:
      return FBAXReadOutcome.failed(outcome.error)
    }
    let attributes = outcome.attributes
    guard let attributes else {
      return FBAXReadOutcome.failed(FBAXBridgeInvariantError(description: "a read reported success but returned no attributes"))
    }

    var node = [String: Any]()
    var readFailures: [String: String]?
    for key in attributes.keys {
      if key == axChildren {
        continue
      }
      let value = attributes[key]
      if let value = value as? NSError {
        if readFailures == nil {
          readFailures = [:]
        }
        var description = try client.localizedDescription(ofError: value)
        if description.value == nil {
          description = try client.description(ofValue: value)
        }
        readFailures?[key] = description.value as String?
      }
      node[key] = try FBAXBridgeJSONSafeValue(client: client, value: value, key: key)
    }
    if let readFailures {
      node[nodeAttributeReadFailures] = readFailures
    }

    var children: [[String: Any]] = []
    let childElements = try outcome.children()
    if depth < maxDepth {
      for child in childElements {
        if budget <= 0 {
          truncated = true
          break
        }
        budget -= 1
        let childOutcome = try FBAXBridgeBuildNode(
          client: client,
          element: child,
          fetchList: fetchList,
          explainUnreachable: explainUnreachable,
          depth: depth + 1,
          maxDepth: maxDepth,
          budget: &budget,
          truncated: &truncated
        )
        if childOutcome.status == FBAXReadStatus.read, let attributes = childOutcome.attributes {
          children.append(attributes)
        }
      }
    } else if !childElements.isEmpty {
      truncated = true
    }
    node[axChildren] = children

    var centre: CGPoint = .zero
    if explainUnreachable,
      try FBAXBridgeNodeIsUnreachable(node: node),
      try FBAXBridgeNodeCentre(client: client, node: node, point: &centre)
    {
      let explanation = try FBAXBridgeExplanationAtPoint(client: client, point: centre)
      if let explanation {
        node[nodeExplainedBy] = explanation
      }
    }
    return FBAXReadOutcome.read(node)
  }

  // MARK: - Translator vocabulary

  // Builds a node through the translator's vocabulary, keyed the same way the XCTest walk keys it where the
  // two vocabularies agree, so the serializer above needs no knowledge of which one produced a tree. The two
  // attributes XCTest has no counterpart for — `enabled` and the translator's own `role` — are keyed in the
  // reader's namespace instead; see `kNodeIsEnabled` and `kNodeTranslatorRole`.
  fileprivate func FBAXBridgeBuildTranslatorNode(
    client: FBAXClient,
    element: FBAXElement,
    depth: Int,
    maxDepth: Int,
    budget: inout Int,
    truncated: inout Bool
  ) throws -> [String: Any]? {
    if budget <= 0 {
      truncated = true
      return nil
    }
    budget -= 1

    FBAXBridgeCountRoundTrip()
    let values = try client.translatorAttributes(of: element)
    // Nil is "could not read", not "empty element": building a node from it would report a failed bind as a
    // healthy application with no content.
    guard values.isAvailable else {
      return nil
    }
    var node = [String: Any]()
    if values.label != nil {
      node[axLabel] = values.label
    }
    if values.identifier != nil {
      node[axIdentifier] = values.identifier
    }
    if values.value != nil {
      node[axValue] = try FBAXBridgeJSONSafeValue(
        client: client,
        value: values.value,
        key: axValue
      )
    }
    if values.frame != nil {
      node[axFrame] = try FBAXBridgeJSONSafeValue(
        client: client,
        value: values.frame,
        key: axFrame
      )
    }
    if values.visible != nil {
      node[axisVisible] = values.visible
    }
    if values.enabled != nil {
      node[nodeIsEnabled] = values.enabled
    }
    if values.role != nil {
      node[nodeTranslatorRole] = values.role
    }
    if values.subrole != nil {
      node[nodeTranslatorSubrole] = values.subrole
    }
    if values.traits != nil {
      node[nodeTraits] = values.traits
    }
    if values.memoryAddress != nil {
      node[nodeElementIdentity] = values.memoryAddress
    }
    // Keyed as XCTest names it, because the host derives `interactable` from that key and the two answer
    // the same question. Without it the derivation has hittability and no point, which is the shape it
    // reports as no verdict at all.
    if values.visiblePoint != nil {
      node[axVisiblePoint] = try FBAXBridgeJSONSafeValue(
        client: client,
        value: values.visiblePoint,
        key: axVisiblePoint
      )
    }

    var children: [Any] = []
    // Children are a separate request (the handler special-cases the attribute out of the batch). Asked even
    // at the depth cap, because `truncated` needs to know whether this node has children.
    FBAXBridgeCountRoundTrip()
    let childElements = try client.translatorChildren(of: element)
    if depth < maxDepth {
      for child in childElements {
        let built = try FBAXBridgeBuildTranslatorNode(
          client: client,
          element: child,
          depth: depth + 1,
          maxDepth: maxDepth,
          budget: &budget,
          truncated: &truncated
        )
        if let built {
          children.append(built)
        }
      }
    } else if !childElements.isEmpty {
      truncated = true
    }
    node[axChildren] = children
    return node
  }

  // MARK: - Modal detection

  // Recursively scans a built node for the concrete alert classes. `SBAlertItemWindow` (a SpringBoard
  // system alert window) sets `*hasSystemAlertWindow`; the first `_UIAlertController*` view captures the
  // alert's element type and label (its title). Reads the same keys the tree carries on the wire.
  fileprivate func FBAXBridgeScanForAlert(
    node: [String: Any],
    hasSystemAlertWindow: inout Bool,
    alertElementType: inout String?,
    alertLabel: inout String?
  ) {
    if let elementType = node[axElementType] as? String {
      if elementType == systemAlertWindowClass {
        hasSystemAlertWindow = true
      }
      if alertElementType == nil && elementType.hasPrefix(alertControllerClassPrefix) {
        alertElementType = elementType
        if let label = node[axLabel] as? String, !label.isEmpty {
          alertLabel = label
        }
      }
    }
    if let children = node[axChildren] as? [Any] {
      for child in children {
        if let child = child as? [String: Any] {
          FBAXBridgeScanForAlert(
            node: child,
            hasSystemAlertWindow: &hasSystemAlertWindow,
            alertElementType: &alertElementType,
            alertLabel: &alertLabel
          )
        }
      }
    }
  }

  // A fullscreen-modal descriptor for a built tree, or nil when none is present. `kind` is `system` when
  // a SpringBoard alert window is present (a system/permission alert), otherwise `app` (an in-app UIKit
  // alert). Host-facing enrichment: the host reads this to detect a modal without geometry.
  fileprivate func FBAXBridgeModalDescriptor(tree: [String: Any]) -> [String: String]? {
    var hasSystemAlertWindow = false
    var alertElementType: String?
    var alertLabel: String?
    FBAXBridgeScanForAlert(
      node: tree,
      hasSystemAlertWindow: &hasSystemAlertWindow,
      alertElementType: &alertElementType,
      alertLabel: &alertLabel
    )
    guard hasSystemAlertWindow || alertElementType != nil else {
      return nil
    }
    var modal = [String: String]()
    modal[modalKind] = hasSystemAlertWindow ? modalKindSystem : modalKindApp
    modal[modalElementType] = alertElementType ?? systemAlertWindowClass
    if let alertLabel {
      modal[modalLabel] = alertLabel
    }
    return modal
  }

  // MARK: - Frontmost resolution

  // Resolves the frontmost application positionally: a system-wide hit-test at the caller's screen anchor
  // reads whichever element owns that point, and its owning pid is the frontmost app.
  //
  // A *positional* proxy for frontmost: agrees with the window server for a fullscreen app or the home
  // screen, but a centred element owned by another process (e.g. a system modal) answers that process.
  fileprivate func FBAXBridgeCenterPointFrontmost(
    client: FBAXClient,
    anchor: CGPoint
  ) throws -> FBAXFrontmostOutcome {
    FBAXBridgeCountRoundTrip()
    let outcome = try client.hitTest(at: anchor, processIdentifier: 0)
    switch outcome.status {
    case FBAXHitTestStatus.hit:
      return FBAXFrontmostOutcome.resolved(outcome.owningProcessIdentifier)
    case FBAXHitTestStatus.empty:
      return FBAXFrontmostOutcome.unresolved(String(format: "system-wide hit-test at (%.1f, %.1f) found no element", anchor.x, anchor.y))
    case FBAXHitTestStatus.applicationUnavailable:
      return FBAXFrontmostOutcome.applicationUnavailable(String(format: "no accessibility server answered the system-wide hit-test at (%.1f, %.1f)", anchor.x, anchor.y))
    case FBAXHitTestStatus.applicationNotResponding:
      return FBAXFrontmostOutcome.applicationNotResponding(String(format: "the application at (%.1f, %.1f) did not answer the system-wide hit-test in time", anchor.x, anchor.y))
    case FBAXHitTestStatus.failed:
      fallthrough
    @unknown default:
      return FBAXFrontmostOutcome.unresolved(outcome.failureReason ?? "the system-wide hit-test failed")
    }
  }

  // `center-point` is the positional hit-test at `anchor`; `window-server` (default) is the in-guest
  // AXPTranslator query; `runningboard` reads RunningBoard's visibility endowment. No fallback between
  // them: a caller who asked for the authoritative answer is not served by silently getting the proxy.
  fileprivate func FBAXBridgeResolveFrontmost(
    client: FBAXClient,
    method: String,
    anchor: CGPoint
  ) throws -> FBAXFrontmostOutcome {
    if method == methodCenterPoint {
      return try FBAXBridgeCenterPointFrontmost(client: client, anchor: anchor)
    }
    if method == methodWindowServer {
      return try client.windowServerFrontmost()
    }
    if method == methodRunningBoard {
      return try client.runningBoardFrontmost()
    }
    return FBAXFrontmostOutcome.unresolved("unsupported frontmost method: \(method)")
  }

  // MARK: - Request handling

  fileprivate func FBAXBridgeErrorResponse(message: String) -> [String: Any] {
    [responseOk: false, responseError: message]
  }

  // A failure the host can act on: the message says what happened, the kind says what class of thing it
  // was, and the pid names the process it was about when there is one. A display-wide hit-test that nothing
  // answers has no pid to name, so it is optional rather than a sentinel the host has to know to ignore.
  fileprivate func FBAXBridgeTaggedErrorResponse(
    message: String,
    kind: String,
    pid: NSNumber?
  ) -> [String: Any] {
    var response: [String: Any] = [responseOk: false, responseError: message, responseErrorKind: kind]
    if let pid {
      response[responsePid] = pid
    }
    return response
  }

  // The response a failed read answers with, or nil when it succeeded. Only the XCTest read produces these
  // statuses, which is why the translator path spends a round trip to obtain one.
  fileprivate func FBAXBridgeReadFailureResponse(
    client: FBAXClient,
    status: FBAXReadStatus,
    readError: Error?,
    pid: pid_t
  ) throws -> [String: Any]? {
    switch status {
    case FBAXReadStatus.read:
      return nil
    case FBAXReadStatus.applicationUnavailable:
      return FBAXBridgeTaggedErrorResponse(
        message: "pid \(pid) has no accessibility server",
        kind: errorKindApplicationUnavailable,
        pid: pid as NSNumber
      )
    case FBAXReadStatus.applicationNotResponding:
      return FBAXBridgeTaggedErrorResponse(
        message: "pid \(pid) did not answer the read of its element tree in time",
        kind: errorKindApplicationNotResponding,
        pid: pid as NSNumber
      )
    case FBAXReadStatus.failed:
      fallthrough
    @unknown default:
      let description = try client.localizedDescription(ofError: readError)
      return FBAXBridgeErrorResponse(message: "failed to read the element tree for pid \(pid): \(description.value ?? "the accessibility runtime reported no error")")
    }
  }

  // How many boundary continuations one read may fetch. Depth and node budget already bound the recursion
  // — a continuation replaces a node at its own depth and never re-triggers on its own root, so every
  // further boundary sits at least one level deeper — but each continuation is fetched before the node it
  // replaces is counted, and this caps what a pathological ownership graph can spend on fetches. Screens
  // measured so far carry one or two boundaries; a read that hits the cap reports `truncated`.
  private let snapshotBoundaryFetchBudget = 64
  // Maps a snapshot lazily so the caller's budgets also bound cross-process continuations.
  // A continuation failure leaves the stub childless; an exception aborts the whole request.
  fileprivate func FBAXBridgeNodeFromSnapshot(
    client: FBAXClient,
    snapshotNode: FBAXSnapshotNode,
    fetchList: [String],
    ownerPid: pid_t,
    depth: Int,
    maxDepth: Int,
    budget: inout Int,
    boundaryFetches: inout Int,
    truncated: inout Bool
  ) throws -> [String: Any]? {
    let valid = try snapshotNode.valid()
    guard valid.boolValue else {
      return nil
    }
    if budget <= 0 {
      truncated = true
      return nil
    }

    let nesting = try snapshotNode.children()
    if ownerPid != 0 && nesting.isEmpty {
      let processIdentifier = try client.snapshots.processIdentifier(for: snapshotNode)
      let elementPid = processIdentifier.int32Value
      if elementPid != 0 && elementPid != ownerPid {
        if depth >= maxDepth || boundaryFetches <= 0 {
          // A bound stopped the continuation, so the subtree is missing for the same reason one below the
          // depth cap is — and is reported the same way.
          truncated = true
        } else {
          boundaryFetches -= 1
          FBAXBridgeCountRoundTrip()
          let continuation = try client.snapshots.readContinuation(snapshotNode, attributeNames: fetchList)
          if let root = continuation.root {
            return try FBAXBridgeNodeFromSnapshot(
              client: client,
              snapshotNode: root,
              fetchList: fetchList,
              ownerPid: elementPid,
              depth: depth,
              maxDepth: maxDepth,
              budget: &budget,
              boundaryFetches: &boundaryFetches,
              truncated: &truncated
            )
          }
          // Fall through and map the stub: absence, not an error, is also the walk's answer at a boundary
          // it cannot cross.
        }
      }
    }
    budget -= 1

    let attributes = try snapshotNode.attributes()
    var node = [String: Any]()
    for attribute in attributes {
      node[attribute.name] = try FBAXBridgeJSONSafeValue(
        client: client,
        value: attribute.value,
        key: attribute.name
      )
    }

    if depth >= maxDepth {
      if !nesting.isEmpty {
        truncated = true
      }
      return node
    }

    var children: [Any] = []
    for child in nesting {
      let built = try FBAXBridgeNodeFromSnapshot(
        client: client,
        snapshotNode: child,
        fetchList: fetchList,
        ownerPid: ownerPid,
        depth: depth + 1,
        maxDepth: maxDepth,
        budget: &budget,
        boundaryFetches: &boundaryFetches,
        truncated: &truncated
      )
      if let built {
        children.append(built)
      }
    }
    node[axChildren] = children
    return node
  }

  // Answers `hittest`: one round trip reading only the element at the point. With no pid it is
  // display-wide, so the host learns the owning app without a separate frontmost query.
  fileprivate func FBAXBridgeHitTest(
    client: FBAXClient,
    request: [String: Any]
  ) throws -> [String: Any] {
    let xNumber = request[requestX] as? NSNumber
    let yNumber = request[requestY] as? NSNumber
    guard xNumber != nil && yNumber != nil else {
      return FBAXBridgeTaggedErrorResponse(
        message: "hittest requires numeric x and y",
        kind: errorKindBadRequest,
        pid: nil
      )
    }
    let pidNumber = request[requestPid] as? NSNumber

    FBAXBridgeCountRoundTrip()

    let outcome = try client.hitTest(at: CGPoint(x: xNumber?.doubleValue ?? 0.0, y: yNumber?.doubleValue ?? 0.0), processIdentifier: pidNumber?.int32Value ?? 0)
    switch outcome.status {
    case FBAXHitTestStatus.hit:
      break
    case FBAXHitTestStatus.applicationUnavailable:
      return FBAXBridgeTaggedErrorResponse(
        message: pidNumber != nil ? "pid \((pidNumber?.int32Value ?? 0)) has no accessibility server to hit-test" : "no accessibility server answered the system-wide hit-test",
        kind: errorKindApplicationUnavailable,
        pid: pidNumber
      )
    case FBAXHitTestStatus.applicationNotResponding:
      return FBAXBridgeTaggedErrorResponse(
        message: pidNumber != nil ? "pid \((pidNumber?.int32Value ?? 0)) did not answer the hit-test in time" : "the application at the hit-test point did not answer in time",
        kind: errorKindApplicationNotResponding,
        pid: pidNumber
      )
    case FBAXHitTestStatus.empty:
      return [responseOk: true, responseEmpty: true]
    case FBAXHitTestStatus.failed:
      fallthrough
    @unknown default:
      return FBAXBridgeErrorResponse(message: outcome.failureReason ?? "the hit-test failed")
    }

    var budget = 1
    var truncated = false
    // maxDepth 0 reads just the hit element's own attributes (no child recursion) — the leaf at the point.
    let hitElement = outcome.element
    guard let hitElement else {
      return FBAXBridgeErrorResponse(message: "the hit-test reported an element but returned none")
    }
    let read = try FBAXBridgeBuildNode(
      client: client,
      element: hitElement,
      fetchList: FBAXBridgeFetchListForRequest(request: request),
      explainUnreachable: false,
      depth: 0,
      maxDepth: 0,
      budget: &budget,
      truncated: &truncated
    )
    switch read.status {
    case FBAXReadStatus.read:
      break
    case FBAXReadStatus.applicationUnavailable:
      return FBAXBridgeTaggedErrorResponse(
        message: "pid \(outcome.owningProcessIdentifier) has no accessibility server",
        kind: errorKindApplicationUnavailable,
        pid: outcome.owningProcessIdentifier as NSNumber
      )
    case FBAXReadStatus.applicationNotResponding:
      return FBAXBridgeTaggedErrorResponse(
        message: "pid \(outcome.owningProcessIdentifier) did not answer the read of the hit element in time",
        kind: errorKindApplicationNotResponding,
        pid: outcome.owningProcessIdentifier as NSNumber
      )
    case FBAXReadStatus.failed:
      fallthrough
    @unknown default:
      return FBAXBridgeErrorResponse(message: "failed to read the hit element")
    }
    let node = read.attributes
    guard let node else {
      return FBAXBridgeErrorResponse(message: "the hit element read reported success but returned no attributes")
    }
    return [responseOk: true, responseTree: node, responsePid: outcome.owningProcessIdentifier as NSNumber]
  }

  // MARK: - Writes

  // The semantic action a wire name asks for. Answers NO for a name this guest does not know, leaving
  // `*action` untouched — an unrecognised action must be refused rather than quietly becoming a press.
  fileprivate func FBAXBridgeActionForName(name: String, action: inout FBAXAction) -> Bool {
    if name == actionPress {
      action = FBAXAction.press
    } else if name == actionScrollUp {
      action = FBAXAction.scrollUp
    } else if name == actionScrollDown {
      action = FBAXAction.scrollDown
    } else if name == actionScrollLeft {
      action = FBAXAction.scrollLeft
    } else if name == actionScrollRight {
      action = FBAXAction.scrollRight
    } else if name == actionScrollToVisible {
      action = FBAXAction.scrollToVisible
    } else {
      return false
    }
    return true
  }

  // Compared in the coerced wire form: the host derived the assertion from a tree it read off this wire.
  fileprivate func FBAXBridgeAttributeMatches(
    client: FBAXClient,
    actual: Any?,
    expected: String
  ) throws -> Bool {
    try client.matches(actual, expected: expected).boolValue
  }

  fileprivate func FBAXBridgeWriteArgumentError(request: [String: Any]) -> [String: Any]? {
    guard request[requestX] is NSNumber && request[requestY] is NSNumber else {
      return FBAXBridgeTaggedErrorResponse(
        message: "a write requires numeric x and y",
        kind: errorKindBadRequest,
        pid: nil
      )
    }
    let assertKey = request[requestAssertKey] as? String
    let assertValue = request[requestAssertValue] as? String
    if (assertKey == nil) != (assertValue == nil) {
      return FBAXBridgeTaggedErrorResponse(
        message: "\(requestAssertKey) and \(requestAssertValue) are only meaningful together",
        kind: errorKindBadRequest,
        pid: nil
      )
    }
    // Only a fetched attribute can be asserted on: the host built the assertion from a node it read, so a
    // key this request does not fetch cannot have come from there.
    if let assertKey, !FBAXBridgeFetchListForRequest(request: request).contains(assertKey) {
      return FBAXBridgeTaggedErrorResponse(
        message: "\(assertKey) is not an attribute a write can assert on",
        kind: errorKindBadRequest,
        pid: nil
      )
    }
    return nil
  }

  // Between the host's read and this hit-test the element under the point can have changed (occlusion, a
  // non-rectangular element, a screen that moved on). Checking one attribute of what is actually there is
  // what stops the action landing somewhere else.
  fileprivate func FBAXBridgeResolveWriteTarget(
    client: FBAXClient,
    request: [String: Any],
    element: inout FBAXElement?,
    pid: inout pid_t
  ) throws -> FBAXWriteOutcome? {
    let xNumber = request[requestX] as? NSNumber
    let yNumber = request[requestY] as? NSNumber
    let assertKey = request[requestAssertKey] as? String
    let assertValue = request[requestAssertValue] as? String

    let pidNumber = request[requestPid] as? NSNumber
    FBAXBridgeCountRoundTrip()
    let hit = try client.hitTest(at: CGPoint(x: xNumber?.doubleValue ?? 0.0, y: yNumber?.doubleValue ?? 0.0), processIdentifier: pidNumber?.int32Value ?? 0)
    switch hit.status {
    case FBAXHitTestStatus.hit:
      break
    case FBAXHitTestStatus.empty:
      return FBAXWriteOutcome.empty()
    case FBAXHitTestStatus.applicationUnavailable:
      return FBAXWriteOutcome.applicationUnavailable()
    case FBAXHitTestStatus.applicationNotResponding:
      return FBAXWriteOutcome.applicationNotResponding()
    case FBAXHitTestStatus.failed:
      fallthrough
    @unknown default:
      return FBAXWriteOutcome.failed(hit.failureReason ?? "the hit-test failed")
    }
    let hitElement = hit.element
    guard let hitElement else {
      return FBAXWriteOutcome.failed("the hit-test reported an element but returned none")
    }

    if let assertKey {
      FBAXBridgeCountRoundTrip()
      let read = try client.readAttributes([assertKey], of: hitElement)
      switch read.status {
      case FBAXReadStatus.read:
        break
      case FBAXReadStatus.applicationUnavailable:
        return FBAXWriteOutcome.applicationUnavailable()
      case FBAXReadStatus.applicationNotResponding:
        return FBAXWriteOutcome.applicationNotResponding()
      // An assertion that cannot be read is not an assertion that failed — the caller is owed the
      // difference between "the screen moved" and "the element could not be inspected".
      case FBAXReadStatus.failed:
        fallthrough
      @unknown default:
        return FBAXWriteOutcome.failed("could not read \(assertKey) to check the assertion")
      }
      let actual = try FBAXBridgeJSONSafeValue(
        client: client,
        value: read.attributes?[assertKey],
        key: assertKey
      )
      let matches = try FBAXBridgeAttributeMatches(
        client: client,
        actual: actual,
        expected: assertValue ?? ""
      )
      if !matches {
        let description = try client.description(ofValue: actual)
        return FBAXWriteOutcome.assertionFailed(String(format: "the element at (%.1f, %.1f) has %@ %@, expected %@", xNumber?.doubleValue ?? 0.0, yNumber?.doubleValue ?? 0.0, assertKey, description.value ?? "(null)", assertValue ?? ""))
      }
    }

    element = hitElement
    pid = hit.owningProcessIdentifier
    return nil
  }

  // The envelope a write outcome is reported in. Total over the status, so every way a write can end has one
  // answer decided in one place rather than per verb.
  fileprivate func FBAXBridgeWriteResponse(outcome: FBAXWriteOutcome, pid: pid_t) -> [String: Any] {
    switch outcome.status {
    case FBAXWriteStatus.written:
      return [responseOk: true, responsePid: pid as NSNumber]
    case FBAXWriteStatus.empty:
      return [responseOk: true, responseEmpty: true]
    case FBAXWriteStatus.assertionFailed:
      return [responseOk: false, responseError: outcome.failureReason ?? "the element at the point is not the one named", responseErrorKind: errorKindAssertionFailed]
    case FBAXWriteStatus.applicationUnavailable:
      return FBAXBridgeTaggedErrorResponse(
        message: pid > 0 ? "pid \(pid) has no accessibility server to accept the write" : "no accessibility server answered the write",
        kind: errorKindApplicationUnavailable,
        pid: pid > 0 ? pid as NSNumber : nil
      )
    case FBAXWriteStatus.applicationNotResponding:
      return FBAXBridgeTaggedErrorResponse(
        message: pid > 0 ? "pid \(pid) did not answer the write in time" : "the application did not answer the write in time",
        kind: errorKindApplicationNotResponding,
        pid: pid > 0 ? pid as NSNumber : nil
      )
    case FBAXWriteStatus.failed:
      fallthrough
    @unknown default:
      return FBAXBridgeErrorResponse(message: outcome.failureReason ?? "the write failed")
    }
  }

  // Answers `perform`. No pre-check that the element accepts the action — see
  // `+[FBAXWriteOutcome outcomeForWriteError:]`.
  fileprivate func FBAXBridgePerform(
    client: FBAXClient,
    request: [String: Any]
  ) throws -> [String: Any] {
    let requestedAction = request[requestAction]
    let name = requestedAction as? String
    var action = FBAXAction.press
    guard let name, FBAXBridgeActionForName(name: name, action: &action) else {
      return FBAXBridgeTaggedErrorResponse(
        message: "unsupported action: \(try FBAXWireValue.formattedDescription(of: requestedAction ?? "(nil)"))",
        kind: errorKindBadRequest,
        pid: nil
      )
    }
    let argumentError = FBAXBridgeWriteArgumentError(request: request)
    if let argumentError {
      return argumentError
    }

    var element: FBAXElement?
    var pid: pid_t = 0
    var outcome = try FBAXBridgeResolveWriteTarget(
      client: client,
      request: request,
      element: &element,
      pid: &pid
    )
    if outcome == nil, let element {
      FBAXBridgeCountRoundTrip()
      outcome = try client.perform(action, on: element)
    }
    guard let outcome else {
      throw FBAXBridgeInvariantError(description: "the write resolved no target or outcome")
    }
    return FBAXBridgeWriteResponse(outcome: outcome, pid: pid)
  }

  // Answers `setvalue`. Nothing an element reports says whether its value is writable, so — as with a
  // `perform` — the runtime's own answer is the only judgement.
  fileprivate func FBAXBridgeSetValue(
    client: FBAXClient,
    request: [String: Any]
  ) throws -> [String: Any] {
    guard let requestedValue = request[requestValue] as? String else {
      return FBAXBridgeTaggedErrorResponse(
        message: "setvalue requires a string value",
        kind: errorKindBadRequest,
        pid: nil
      )
    }
    let argumentError = FBAXBridgeWriteArgumentError(request: request)
    if let argumentError {
      return argumentError
    }

    var element: FBAXElement?
    var pid: pid_t = 0
    var outcome = try FBAXBridgeResolveWriteTarget(
      client: client,
      request: request,
      element: &element,
      pid: &pid
    )
    if outcome == nil, let element {
      FBAXBridgeCountRoundTrip()
      outcome = try client.setValue(requestedValue, on: element)
    }
    guard let outcome else {
      throw FBAXBridgeInvariantError(description: "the write resolved no target or outcome")
    }
    return FBAXBridgeWriteResponse(outcome: outcome, pid: pid)
  }

  fileprivate func FBAXBridgeDeviceSettingForName(name: String, setting: inout FBAXDeviceSetting) -> Bool {
    if name == "reduce-motion" {
      setting = FBAXDeviceSetting.reduceMotion
    } else if name == "reduce-transparency" {
      setting = FBAXDeviceSetting.reduceTransparency
    } else if name == "button-shapes" {
      setting = FBAXDeviceSetting.buttonShapes
    } else if name == "voiceover" {
      setting = FBAXDeviceSetting.voiceOver
    } else {
      return false
    }
    return true
  }

  fileprivate func FBAXBridgeDeviceSetting(
    client: FBAXClient,
    request: [String: Any],
    shouldSet: Bool
  ) throws -> [String: Any] {
    guard let requestedName = request[requestSetting] as? String else {
      return FBAXBridgeTaggedErrorResponse(
        message: "device settings require a setting name",
        kind: errorKindBadRequest,
        pid: nil
      )
    }
    var setting: FBAXDeviceSetting = .reduceMotion
    guard FBAXBridgeDeviceSettingForName(name: requestedName, setting: &setting) else {
      return FBAXBridgeTaggedErrorResponse(
        message: "unsupported device setting: \(requestedName)",
        kind: errorKindBadRequest,
        pid: nil
      )
    }

    let requestedEnabled = request[requestEnabled] as? NSNumber
    if shouldSet && requestedEnabled == nil {
      return FBAXBridgeTaggedErrorResponse(
        message: "settings-set requires a boolean enabled value",
        kind: errorKindBadRequest,
        pid: nil
      )
    }
    let outcome = shouldSet ? try client.setEnabled((requestedEnabled?.boolValue ?? false), for: setting) : try client.enabledState(for: setting)
    switch outcome.status {
    case FBAXDeviceSettingStatus.resolved:
      return [responseOk: true, responseEnabled: outcome.isEnabled as NSNumber]
    case FBAXDeviceSettingStatus.unavailable:
      return FBAXBridgeTaggedErrorResponse(
        message: outcome.failureReason ?? "device setting \(requestedName) is unavailable",
        kind: errorKindReaderUnavailable,
        pid: nil
      )
    case FBAXDeviceSettingStatus.failed:
      fallthrough
    @unknown default:
      return FBAXBridgeTaggedErrorResponse(
        message: outcome.failureReason ?? "device setting \(requestedName) failed",
        kind: errorKindReaderUnavailable,
        pid: nil
      )
    }
  }

  fileprivate func FBAXBridgeDispatchRequest(request: [String: Any]) throws -> [String: Any] {
    // The frame is JSON from the client, so the value can be of any type — narrow it to a string before
    // comparing, rather than sending `isEqualToString:` to whatever arrived.
    let requestedVerb = request[requestVerb]
    let verb = requestedVerb as? String
    let isDescribe = verb == verbDescribe
    let isHitTest = verb == verbHitTest
    let isPerform = verb == verbPerform
    let isSetValue = verb == verbSetValue
    let isGetDeviceSetting = verb == verbGetDeviceSetting
    let isSetDeviceSetting = verb == verbSetDeviceSetting
    if verb == verbShutdown {
      // Answered here, above the pid check and the runtime bind: shutting down needs neither, and a
      // reader that cannot bind is exactly the one a caller most wants to be able to end.
      return [responseOk: true, responseShutdown: true]
    }
    guard isDescribe || isHitTest || isPerform || isSetValue || isGetDeviceSetting || isSetDeviceSetting else {
      return FBAXBridgeTaggedErrorResponse(
        message: "unsupported verb: \(try FBAXWireValue.formattedDescription(of: requestedVerb ?? "(nil)"))",
        kind: errorKindBadRequest,
        pid: nil
      )
    }
    // Process-addressed verbs reject non-positive pids before runtime setup. Device-setting verbs carry no
    // pid, but an explicitly malformed one is still refused rather than silently ignored.
    let requestedPid = request[requestPid] as? NSNumber
    if let requestedPid, requestedPid.int32Value <= 0 {
      return FBAXBridgeTaggedErrorResponse(
        message: "pid \(requestedPid.int32Value) names no application",
        kind: errorKindApplicationUnavailable,
        pid: requestedPid
      )
    }

    let client: FBAXClient
    do {
      client = try FBAXClientProvider.client()
    } catch {
      return FBAXBridgeTaggedErrorResponse(
        message: error.localizedDescription,
        kind: errorKindReaderUnavailable,
        pid: nil
      )
    }

    if isGetDeviceSetting || isSetDeviceSetting {
      return try FBAXBridgeDeviceSetting(
        client: client,
        request: request,
        shouldSet: isSetDeviceSetting
      )
    }
    // `hittest` is self-contained: with a pid it hit-tests that app; with no pid it hit-tests display-wide
    // — the app owning the point, resolved in-guest, with no frontmost pid query.
    if isHitTest {
      return try FBAXBridgeHitTest(client: client, request: request)
    }
    // Writes are point-addressed: a one-shot guest exits between requests, so an element handle cannot
    // survive one.
    if isPerform {
      return try FBAXBridgePerform(client: client, request: request)
    }
    if isSetValue {
      return try FBAXBridgeSetValue(client: client, request: request)
    }
    // `describe`: an explicit `pid` names the app directly; with no pid it is a fused frontmost read — the
    // guest resolves the frontmost app in-guest (via the selected method, anchored at `x`/`y`) and reads
    // its tree in this one call, with no separate pid round-trip.
    var pid: pid_t = 0
    var frontmostMethod: String?
    var frontmostAnchor: CGPoint = .zero
    if let requestedPid {
      pid = requestedPid.int32Value
    } else {
      let xNumber = request[requestX] as? NSNumber
      let yNumber = request[requestY] as? NSNumber
      guard xNumber != nil && yNumber != nil else {
        return FBAXBridgeTaggedErrorResponse(
          message: "describe requires either a numeric pid or the frontmost anchor (x, y)",
          kind: errorKindBadRequest,
          pid: nil
        )
      }
      let requestedMethod = request[requestMethod] as? String
      frontmostMethod = requestedMethod ?? methodWindowServer
      frontmostAnchor = CGPoint(x: xNumber?.doubleValue ?? 0.0, y: yNumber?.doubleValue ?? 0.0)
    }

    // Automation mode determines the structure visible to both frontmost discovery and traversal.
    var automationAsserted = false
    var automation = try client.automationModeEnabled()
    var automationEnabled = automation.boolValue
    if let requestedAutomation = request[requestAutomationMode] as? NSNumber {
      let wanted = requestedAutomation.boolValue
      // Only write when it would change something. A no-op write is still a preference write, and
      // reporting `asserted` for one would tell a caller this read altered a device it left alone.
      if wanted != automationEnabled {
        automation = try client.setAutomationModeEnabled(wanted)
        automationEnabled = automation.boolValue
        // True only if the write took; a preference write can be accepted and not apply.
        automationAsserted = automationEnabled == wanted
      }
    }

    if let frontmostMethod {
      let frontmost = try FBAXBridgeResolveFrontmost(
        client: client,
        method: frontmostMethod,
        anchor: frontmostAnchor
      )
      switch frontmost.status {
      case FBAXFrontmostStatus.resolved:
        break
      case FBAXFrontmostStatus.applicationUnavailable:
        return FBAXBridgeTaggedErrorResponse(
          message: frontmost.failureReason ?? "nothing frontmost has an accessibility server",
          kind: errorKindApplicationUnavailable,
          pid: nil
        )
      case FBAXFrontmostStatus.applicationNotResponding:
        return FBAXBridgeTaggedErrorResponse(
          message: frontmost.failureReason ?? "the frontmost application did not answer in time",
          kind: errorKindApplicationNotResponding,
          pid: nil
        )
      case FBAXFrontmostStatus.unresolved:
        fallthrough
      @unknown default:
        return FBAXBridgeTaggedErrorResponse(
          message: frontmost.failureReason ?? "could not resolve the frontmost application pid",
          kind: errorKindFrontmostUnresolved,
          pid: nil
        )
      }
      pid = frontmost.processIdentifier
    }

    let application = try client.applicationElement(forProcessIdentifier: pid)
    let root = application.value
    guard let root else {
      return FBAXBridgeErrorResponse(message: "no application element for pid \(pid)")
    }

    let maxDepth = (request[requestMaxDepth] as? NSNumber).map { Int($0.int32Value) } ?? defaultMaxDepth
    var budget = (request[requestMaxNodes] as? NSNumber).map { Int($0.int32Value) } ?? defaultNodeBudget

    var truncated = false
    var tree: [String: Any]?
    gRoundTrips = 0
    let traverseStarted = CFAbsoluteTimeGetCurrent()
    if try FBAXWireValue.boolean(from: request[requestSnapshotTree]).boolValue == true {
      let names = FBAXBridgeFetchListForRequest(request: request)
      let snapshot = try client.snapshots.read(root, attributeNames: names)
      guard let snapshotRoot = snapshot.root else {
        let description = try client.localizedDescription(ofError: snapshot.error)
        return FBAXBridgeTaggedErrorResponse(
          message: (description.value as String?) ?? "the single-fetch read returned no tree",
          kind: errorKindApplicationNotResponding,
          pid: pid as NSNumber
        )
      }
      // One fetch for the whole tree, counted up-front so the boundary continuations the mapper fetches
      // land on top of it.
      gRoundTrips = 1
      // The owner every node's element is compared against, read from the snapshot's own root element
      // rather than taken from the request: the two agree on a live runtime, and a runtime that cannot
      // attribute elements answers 0, which disables boundary continuation rather than mistargeting it.
      let processIdentifier = try client.snapshots.processIdentifier(for: snapshotRoot)
      let ownerPid = processIdentifier.int32Value
      var boundaryFetches = snapshotBoundaryFetchBudget
      tree = try FBAXBridgeNodeFromSnapshot(
        client: client,
        snapshotNode: snapshotRoot,
        fetchList: names,
        ownerPid: ownerPid,
        depth: 0,
        maxDepth: maxDepth,
        budget: &budget,
        boundaryFetches: &boundaryFetches,
        truncated: &truncated
      )
      if tree == nil {
        return FBAXBridgeErrorResponse(message: "the single-fetch read returned a shape with no root node")
      }
    } else if try FBAXWireValue.boolean(from: request[requestTranslatorVocabulary]).boolValue == true {
      // Whether the application is there at all is a question only the XCTest read answers. The runtime
      // vends an application element for any pid, including one that names no process, and the translator
      // answers against it with synthesized defaults rather than failing — so without this check the read
      // would report a healthy tree for a dead process. One extra round trip, on the opt-in path only.
      let availability = try client.readAttributes([axElementType], of: root)
      let unavailable = try FBAXBridgeReadFailureResponse(
        client: client,
        status: availability.status,
        readError: availability.error,
        pid: pid
      )
      if let unavailable {
        return unavailable
      }
      tree = try FBAXBridgeBuildTranslatorNode(
        client: client,
        element: root,
        depth: 0,
        maxDepth: maxDepth,
        budget: &budget,
        truncated: &truncated
      )
      if tree == nil {
        return FBAXBridgeErrorResponse(message: "the translator vocabulary returned no attributes for this element")
      }
    } else {
      let read = try FBAXBridgeBuildNode(
        client: client,
        element: root,
        fetchList: FBAXBridgeFetchListForRequest(request: request),
        explainUnreachable: try FBAXWireValue.boolean(from: request[requestExplainUnreachable]).boolValue,
        depth: 0,
        maxDepth: maxDepth,
        budget: &budget,
        truncated: &truncated
      )
      let failure = try FBAXBridgeReadFailureResponse(
        client: client,
        status: read.status,
        readError: read.error,
        pid: pid
      )
      if let failure {
        return failure
      }
      tree = read.attributes
      if tree == nil {
        return FBAXBridgeErrorResponse(message: "the tree read reported success but returned no attributes")
      }
    }
    // Closed before the response is assembled, so it measures the walk and not the bookkeeping after it.
    let traverseDuration = CFAbsoluteTimeGetCurrent() - traverseStarted

    // Always report the pid read, so the host tags elements with it — for a fused frontmost read the host
    // does not know the pid until now. `method` rides along when the pid was resolved in-guest.
    guard let tree else {
      throw FBAXBridgeInvariantError(description: "the tree read reported success but returned no attributes")
    }
    var response: [String: Any] = [responseOk: true, responseTree: tree, responseTruncated: truncated as NSNumber, responsePid: pid as NSNumber]
    response[responseAutomation] = [kAutomationEnabled: automationEnabled as NSNumber, kAutomationAsserted: automationAsserted as NSNumber]
    response[responsePhases] = [phaseTraverse: (traverseDuration * 1000) as NSNumber, phaseMachRoundTrips: gRoundTrips as NSNumber]
    if let frontmostMethod {
      response[responseMethod] = frontmostMethod
    }
    // Enrich the wire with a fullscreen-modal descriptor when one is present in the tree (host-facing;
    // not emitted in the serialized CLI output).
    let modal = FBAXBridgeModalDescriptor(tree: tree)
    if let modal {
      response[responseModal] = modal
    }
    return response
  }

  // MARK: - Argv front-end

  fileprivate func FBAXBridgeRequestFromArguments(action: String, arguments: [String]) -> [String: Any] {
    let request = FBAXBridgeArguments.request(action: action, arguments: arguments)

    return request
  }

  // MARK: - Testing

  fileprivate func FBAXBridgeWireConstantsForTesting() -> [String: String] {
    [
      "node.elementType": axElementType, "node.elementBaseType": axElementBaseType, "node.label": axLabel, "node.value": axValue, "node.identifier": axIdentifier, "node.frame": axFrame, "node.automationType": axAutomationType, "node.children": axChildren, "request.verb": requestVerb, "request.pid": requestPid, "request.maxDepth": requestMaxDepth, "request.maxNodes": requestMaxNodes, "request.automationMode": requestAutomationMode, "request.attributes": requestAttributes, "request.translatorVocabulary": requestTranslatorVocabulary, "request.explainUnreachable": requestExplainUnreachable, "node.explainedBy": nodeExplainedBy, "node.isEnabled": nodeIsEnabled, "node.translatorRole": nodeTranslatorRole, "node.translatorSubrole": nodeTranslatorSubrole, "node.traits": nodeTraits, "node.elementIdentity": nodeElementIdentity, "request.x": requestX, "request.y": requestY, "request.method": requestMethod, "request.action": requestAction, "request.value": requestValue, "request.setting": requestSetting, "request.enabled": requestEnabled, "request.assertKey": requestAssertKey, "request.assertValue": requestAssertValue, "envelope.ok": responseOk, "envelope.enabled": responseEnabled, "envelope.tree": responseTree, "envelope.error": responseError, "envelope.empty": responseEmpty, "envelope.errorKind": responseErrorKind, "envelope.errorKindApplicationUnavailable": errorKindApplicationUnavailable, "envelope.errorKindApplicationNotResponding": errorKindApplicationNotResponding, "envelope.errorKindFrontmostUnresolved": errorKindFrontmostUnresolved, "envelope.errorKindReaderUnavailable": errorKindReaderUnavailable, "envelope.errorKindBadRequest": errorKindBadRequest, "envelope.errorKindAssertionFailed": errorKindAssertionFailed, "envelope.truncated": responseTruncated, "envelope.pid": responsePid, "envelope.method": responseMethod, "envelope.modal": responseModal, "envelope.automation": responseAutomation, "envelope.phases": responsePhases, "phases.traverse": phaseTraverse,
      "phases.machRoundTrips": phaseMachRoundTrips, "automation.enabled": kAutomationEnabled, "automation.asserted": kAutomationAsserted, "modal.kind": modalKind, "modal.kindSystem": modalKindSystem, "modal.kindApp": modalKindApp, "modal.elementType": modalElementType, "modal.label": modalLabel, "modal.systemAlertWindowClass": systemAlertWindowClass, "modal.alertControllerClassPrefix": alertControllerClassPrefix, "verb.describe": verbDescribe, "verb.hittest": verbHitTest, "verb.perform": verbPerform, "verb.setvalue": verbSetValue, "verb.settingsGet": verbGetDeviceSetting, "verb.settingsSet": verbSetDeviceSetting, "verb.shutdown": verbShutdown, "action.press": actionPress, "action.scrollUp": actionScrollUp, "action.scrollDown": actionScrollDown, "action.scrollLeft": actionScrollLeft, "action.scrollRight": actionScrollRight, "action.scrollToVisible": actionScrollToVisible, "method.centerPoint": methodCenterPoint, "method.windowServer": methodWindowServer, "method.runningBoard": methodRunningBoard,
    ]
  }

}

// Objective-C runtime clients convert private-framework exceptions to NSError before returning here.
// Answer those errors on the shared dispatcher path so the serve connection can handle later requests.
@objc public final class AccessibilityServiceStaticFuncs: NSObject {

  @objc public static func handleRequest(_ request: [String: Any]) -> [String: Any] {
    do {
      return try AccessibilityRequest().FBAXBridgeDispatchRequest(request: request)
    } catch {
      return [responseOk: false, responseError: "the reader raised while answering: \(error.localizedDescription)"]
    }
  }

  @objc public static func handleRequestData(_ data: Data, shutdownRequested: UnsafeMutablePointer<ObjCBool>?) -> [String: Any] {
    let response: [String: Any]
    if let request = FBAXBridgeWire.request(from: data) {
      response = handleRequest(request)
    } else {
      response = [responseOk: false, responseError: "malformed request frame", responseErrorKind: errorKindBadRequest]
    }
    shutdownRequested?.pointee = ObjCBool((response[responseShutdown] as? NSNumber)?.boolValue ?? false)
    return response
  }

  @objc public static func modalDescriptor(_ tree: [String: Any]) -> [String: String]? {
    AccessibilityRequest().FBAXBridgeModalDescriptor(tree: tree)
  }

  @objc public static func wireConstantsForTesting() -> [String: String] {
    AccessibilityRequest().FBAXBridgeWireConstantsForTesting()
  }

  @objc public static func serializeResponse(_ response: [String: Any]) -> Data {
    struct StaticVars {
      static let fallback = "{\"ok\":false,\"error\":\"response serialization failed\"}"
    }
    // Sanitize first (non-finite numbers would otherwise raise), then still guard the call: an
    // unforeseen unserializable value must degrade to an error frame the client can read, never abort
    // the process and sever the connection.
    let sanitized = FBAXBridgeWire.sanitized(response)
    var data: Data?
    if JSONSerialization.isValidJSONObject(sanitized) {
      data = FBAXResponseEncoder.data(for: sanitized)
    } else {
      NSLog("[AccessibilityService] response is not a valid JSON object; emitting an error frame")
    }
    if let data {
      return data
    }
    return Data(StaticVars.fallback.utf8)
  }

  @objc public static func handleAction(_ action: String, arguments: [String], serve: (String, [String]) -> Int32, writeResponse: (Data) -> Void) -> Int32 {
    if action == actionServe {
      guard let socketPath = arguments.first, !socketPath.isEmpty else {
        NSLog("[AccessibilityService] serve requires a socket path argument")
        return 1
      }
      return serve(socketPath, Array(arguments.dropFirst()))
    }
    let request = FBAXBridgeArguments.request(action: action, arguments: arguments)
    let response = handleRequest(request)
    writeResponse(serializeResponse(response))
    return (response[responseOk] as? NSNumber)?.boolValue == true ? 0 : 1
  }
}
