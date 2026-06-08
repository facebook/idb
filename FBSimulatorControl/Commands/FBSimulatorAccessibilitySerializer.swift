/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AccessibilityPlatformTranslation
import AppKit
import FBControlCore
import Foundation

/// Serializes an `AXPMacPlatformElement` tree into the JSON-ready dictionaries
/// emitted by the accessibility commands. The values mirror the old
/// SimulatorBridge implementation for downstream compatibility.
///
/// Still driven by the Objective-C `FBAXTranslationRequest` / remote-content code
/// in this module (via `FBSimulatorControl-Swift.h`), so it keeps `@objc` class
/// methods with the original selectors and `NSMutable*` return types. `public`
/// so it lands in the module's generated header.
@objc(FBSimulatorAccessibilitySerializer)
public final class FBSimulatorAccessibilitySerializer: NSObject {

  private static let axPrefix = "AX"
  private static let discoveryMethodRecursive = "recursive"
  private static let discoveryMethodPointGrid = "point_grid"

  // MARK: - Helpers

  private static func ensureJSONSerializable(_ object: Any?) -> Any {
    guard let object else {
      return NSNull()
    }
    if JSONSerialization.isValidJSONObject([object]) {
      return object
    }
    return String(describing: object)
  }

  private static func customActions(from element: AXPMacPlatformElement) -> [Any] {
    let actions = element.accessibilityCustomActions() ?? []
    return actions.map { ensureJSONSerializable($0.name) }
  }

  // AXTraits is an iOS-specific bitmask that was available in the old
  // SimulatorBridge implementation. Returns nil if the element does not support
  // it (callers convert nil to NSNull). Read via `perform` because the
  // underlying `accessibilityAttributeValue:` is a deprecated NSAccessibility API
  // that is not exposed to Swift.
  private static func traits(from element: AXPMacPlatformElement) -> [String]? {
    let selector = NSSelectorFromString("accessibilityAttributeValue:")
    guard element.responds(to: selector) else {
      return nil
    }
    guard let result = element.perform(selector, with: "AXTraits")?.takeUnretainedValue() as? NSNumber else {
      return nil
    }
    return Array(AXExtractTraits(result.uint64Value))
  }

  // Mirrors ObjC's unchecked typed iteration (`for (AXPMacPlatformElement * in ...)`):
  // children are message-dispatched, so test doubles that respond to the selectors
  // (but are not `AXPMacPlatformElement` subclasses) flow through unchanged. Uses
  // `unsafeBitCast` rather than `unsafeDowncast` because the latter asserts the
  // dynamic type in debug builds, which the doubles would fail.
  private static func children(of element: AXPMacPlatformElement) -> [AXPMacPlatformElement] {
    (element.accessibilityChildren() ?? []).map { unsafeBitCast($0 as AnyObject, to: AXPMacPlatformElement.self) }
  }

  // MARK: - Entry points

  @objc(recursiveDescriptionFromElement:token:nestedFormat:keys:collector:coverageGrid:seenPids:applicationElement:)
  public static func recursiveDescription(
    fromElement element: AXPMacPlatformElement,
    token: String,
    nestedFormat: Bool,
    keys: Set<String>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: NSMutableSet?,
    applicationElement outApplicationElement: AutoreleasingUnsafeMutablePointer<NSMutableDictionary?>?
  ) -> NSMutableArray {
    element.translation?.bridgeDelegateToken = token
    if nestedFormat {
      let appElement = nestedRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids)
      outApplicationElement?.pointee = appElement
      return NSMutableArray(array: [appElement])
    }
    return flatRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids)
  }

  @objc(formattedDescriptionOfElement:token:nestedFormat:keys:collector:coverageGrid:)
  public static func formattedDescription(
    ofElement element: AXPMacPlatformElement,
    token: String,
    nestedFormat: Bool,
    keys: Set<String>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?
  ) -> NSDictionary {
    element.translation?.bridgeDelegateToken = token
    if nestedFormat {
      return nestedRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: nil)
    }
    return accessibilityDictionary(forElement: element, token: token, keys: keys, collector: collector, frontmostPid: 0, coverageGrid: coverageGrid, seenPids: nil, discoveryMethod: discoveryMethodRecursive) as NSDictionary
  }

  // The values here are intended to mirror the values in the old SimulatorBridge
  // implementation for compatibility downstream. `frontmostPid` is accepted for
  // selector compatibility with the remote-content caller; it is unused.
  @objc(accessibilityDictionaryForElement:token:keys:collector:frontmostPid:coverageGrid:seenPids:discoveryMethod:)
  public static func accessibilityDictionary(
    forElement element: AXPMacPlatformElement,
    token: String,
    keys: Set<String>,
    collector: FBAccessibilityProfilingCollector?,
    frontmostPid: pid_t,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: NSMutableSet?,
    discoveryMethod: String
  ) -> [String: Any] {
    // The token must always be set so that the right callback is called.
    element.translation?.bridgeDelegateToken = token

    let elementPid = element.translation?.pid ?? 0
    seenPids?.add(NSNumber(value: elementPid))

    collector?.incrementElementCount()

    var values: [String: Any] = [:]

    // Includes a key (with JSON serialization) only when requested, incrementing
    // the profiling counter and reading the value lazily so attribute access is
    // tracked exactly as the ObjC macro did.
    func include(_ key: FBAXKeys, _ value: @autoclosure () -> Any?) {
      let rawKey = key.rawValue
      guard keys.contains(rawKey) else {
        return
      }
      collector?.incrementAttributeFetchCount(forKey: rawKey)
      values[rawKey] = ensureJSONSerializable(value())
    }

    // Frame is always computed since it is used by multiple keys and the coverage grid.
    collector?.incrementAttributeFetchCount(forKey: FBAXKeys.frame.rawValue)
    let frame = element.accessibilityFrame()

    // Role is used by multiple keys and needs processing. Check Role first to
    // assign rawRole, then Type can derive from it.
    var role: String?
    var rawRole: String?
    if keys.contains(FBAXKeys.role.rawValue) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.role.rawValue)
      rawRole = element.accessibilityRole()?.rawValue
      values[FBAXKeys.role.rawValue] = ensureJSONSerializable(rawRole)
    }
    if keys.contains(FBAXKeys.type.rawValue) {
      if rawRole == nil {
        collector?.incrementAttributeFetchCount(forKey: FBAXKeys.type.rawValue)
        rawRole = element.accessibilityRole()?.rawValue
      }
      // accessibilityRole may be prefixed with "AX"; strip it to match the
      // SimulatorBridge implementation.
      if let rawRole, rawRole.hasPrefix(axPrefix) {
        role = String(rawRole.dropFirst(2))
      } else {
        role = rawRole
      }
    }

    // Mark frame in coverage grid (for non-Application elements).
    if let coverageGrid {
      if rawRole == nil {
        collector?.incrementAttributeFetchCount(forKey: nil)
        rawRole = element.accessibilityRole()?.rawValue
      }
      let isApplication = rawRole == "AXApplication" || rawRole == "Application"
      if !isApplication {
        coverageGrid.markFilled(with: frame)
      }
    }

    // Legacy values that mirror SimulatorBridge.
    include(.label, element.accessibilityLabel())
    if keys.contains(FBAXKeys.frame.rawValue) {
      values[FBAXKeys.frame.rawValue] = NSStringFromRect(frame)
    }
    include(.value, element.accessibilityValue())
    include(.uniqueID, element.accessibilityIdentifier())

    // Synthetic values.
    if keys.contains(FBAXKeys.type.rawValue) {
      values[FBAXKeys.type.rawValue] = ensureJSONSerializable(role)
    }

    // New values.
    include(.title, element.accessibilityTitle())
    if keys.contains(FBAXKeys.frameDict.rawValue) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.frameDict.rawValue)
      values[FBAXKeys.frameDict.rawValue] = [
        "x": frame.origin.x,
        "y": frame.origin.y,
        "width": frame.size.width,
        "height": frame.size.height,
      ]
    }
    include(.help, element.accessibilityHelp())
    // The boolean NSAccessibility attributes are read through `as AnyObject` to
    // force dynamic `objc_msgSend` dispatch: AppKit's NSAccessibility Swift overlay
    // otherwise devirtualizes these property gets, which would bypass an element
    // (e.g. a test double) that implements the selector but is not an
    // NSAccessibilityElement subclass. It is also nil-safe for elements that do
    // not respond to the selector.
    include(.enabled, (element as AnyObject).isAccessibilityEnabled())
    include(.customActions, customActions(from: element))
    include(.roleDescription, element.accessibilityRoleDescription())
    include(.subrole, element.accessibilitySubrole()?.rawValue)
    include(.contentRequired, (element as AnyObject).isAccessibilityRequired())
    include(.pid, element.translation?.pid ?? 0)
    if keys.contains(FBAXKeys.traits.rawValue) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.traits.rawValue)
      values[FBAXKeys.traits.rawValue] = traits(from: element) ?? NSNull()
    }
    include(.expanded, (element as AnyObject).isAccessibilityExpanded())
    include(.placeholder, element.accessibilityPlaceholderValue())
    include(.hidden, (element as AnyObject).isAccessibilityHidden())
    include(.focused, (element as AnyObject).isAccessibilityFocused())
    include(.isRemote, discoveryMethod)

    return values
  }

  // MARK: - Recursion

  // Non-hierarchical (flat) output: frames are relative to the root, as in SimulatorBridge.
  private static func flatRecursiveDescription(
    fromElement element: AXPMacPlatformElement,
    token: String,
    keys: Set<String>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: NSMutableSet?
  ) -> NSMutableArray {
    let values = NSMutableArray()
    values.add(accessibilityDictionary(forElement: element, token: token, keys: keys, collector: collector, frontmostPid: 0, coverageGrid: coverageGrid, seenPids: seenPids, discoveryMethod: discoveryMethodRecursive))
    for child in children(of: element) {
      child.translation?.bridgeDelegateToken = token
      values.addObjects(from: flatRecursiveDescription(fromElement: child, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids) as [AnyObject])
    }
    return values
  }

  private static func nestedRecursiveDescription(
    fromElement element: AXPMacPlatformElement,
    token: String,
    keys: Set<String>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: NSMutableSet?
  ) -> NSMutableDictionary {
    let values = NSMutableDictionary(dictionary: accessibilityDictionary(forElement: element, token: token, keys: keys, collector: collector, frontmostPid: 0, coverageGrid: coverageGrid, seenPids: seenPids, discoveryMethod: discoveryMethodRecursive))
    let childrenValues = NSMutableArray()
    for child in children(of: element) {
      child.translation?.bridgeDelegateToken = token
      childrenValues.add(nestedRecursiveDescription(fromElement: child, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids))
    }
    values["children"] = childrenValues
    return values
  }
}
