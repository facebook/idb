/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
import ApplicationServices
import FBControlCore
import Foundation

/**
 Fork addition: AXUIElement-based accessibility fetching (macOS System API).

 Uses the macOS `AXUIElement` C API to query Simulator.app's accessibility tree
 directly from the host — the same path Accessibility Inspector uses. Unlike the
 CoreSimulator XPC path, this returns the full bridged iOS hierarchy including
 navigation-bar and tab-bar children that the XPC serializer misses.

 Requires the host process to be trusted for Accessibility (TCC); callers should
 probe `AXIsProcessTrusted()` before invoking. Ported from the pre-rewrite
 Objective-C implementation in `FBSimulatorAccessibilityCommands.m`.
 */
public enum FBAXUIElementAccessibility {

  public enum QueryError: Error, CustomStringConvertible {
    case notTrusted(bundlePath: String)
    case appElementUnavailable(simulatorPID: pid_t)
    case renderableViewNotFound(simulatorPID: pid_t, deviceName: String?, axWindowsError: AXError, axWindowTitles: [String], cgWindowTitles: [String], bundlePath: String)

    public var description: String {
      switch self {
      case .notTrusted(let bundlePath):
        return "AXUIElement accessibility query requires Accessibility permission for bundle \(bundlePath) (AXIsProcessTrusted() returned NO)"
      case .appElementUnavailable(let simulatorPID):
        return "Failed to create AXUIElement for Simulator PID \(simulatorPID)"
      case .renderableViewNotFound(let simulatorPID, let deviceName, let axWindowsError, let axWindowTitles, let cgWindowTitles, let bundlePath):
        return "Could not find SimDisplayRenderableView in Simulator.app (PID \(simulatorPID), device: \(deviceName ?? "any"), AX windows error: \(errorDescription(axWindowsError)), AX window titles: \(axWindowTitles), CG window titles: \(cgWindowTitles), bundle: \(bundlePath))"
      }
    }
  }

  // MARK: - Public

  /**
   Fetches the accessibility elements of the simulator device window rendered by
   Simulator.app with the given PID, synchronously. Heavy AX traffic happens on the
   main queue (Simulator.app activation requires it), so do not call from the main queue.

   - Parameter simulatorPID: the PID of the Simulator.app process.
   - Parameter deviceName: when multiple device windows are open, the device name to match; nil matches any window.
   - Parameter nestedFormat: `true` for a nested tree (children arrays), `false` for a flat array.
   - Returns: an array of JSON-compatible element dictionaries keyed by `FBAXKeys` raw values.
   */
  public static func accessibilityElements(forSimulatorPID simulatorPID: pid_t, deviceName: String?, nestedFormat: Bool) throws -> [[String: Any]] {
    guard AXIsProcessTrusted() else {
      throw QueryError.notTrusted(bundlePath: Bundle.main.bundlePath)
    }

    nonisolated(unsafe) var result: [[String: Any]]?
    nonisolated(unsafe) var innerError: Error?

    let work = {
      NSRunningApplication(processIdentifier: simulatorPID)?.activate(options: .activateAllWindows)
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

      let appRef = AXUIElementCreateApplication(simulatorPID)

      var windowsError: AXError = .success
      var windowTitles: [String] = []
      var renderableView = renderableViewFromSystemWide(deviceName: deviceName, simulatorPID: simulatorPID, windowTitles: &windowTitles)
      if renderableView == nil {
        renderableView = renderableViewFromApp(appRef, deviceName: deviceName, windowsError: &windowsError, windowTitles: &windowTitles)
      }
      guard let renderableView else {
        innerError = QueryError.renderableViewNotFound(
          simulatorPID: simulatorPID,
          deviceName: deviceName,
          axWindowsError: windowsError,
          axWindowTitles: windowTitles,
          cgWindowTitles: cgWindowTitles(forPID: simulatorPID),
          bundlePath: Bundle.main.bundlePath)
        return
      }

      let renderableOrigin = origin(of: renderableView)
      if nestedFormat {
        result = [nestedDictionary(from: renderableView, origin: renderableOrigin)]
      } else {
        result = flatArray(from: renderableView, origin: renderableOrigin)
      }
    }
    if Thread.isMainThread {
      work()
    } else {
      DispatchQueue.main.sync(execute: work)
    }

    if let innerError {
      throw innerError
    }
    guard let result else {
      throw QueryError.appElementUnavailable(simulatorPID: simulatorPID)
    }
    return result
  }

  // MARK: - Renderable View Discovery

  private static func renderableViewFromApp(_ appRef: AXUIElement, deviceName: String?, windowsError: inout AXError, windowTitles: inout [String]) -> AXUIElement? {
    var titles: [String] = []
    defer { windowTitles = titles }

    // First try the focused/main window paths. These often work even when kAXWindowsAttribute
    // intermittently returns kAXErrorCannotComplete for Simulator.app.
    for attributeName in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
      guard let window = elementAttribute(appRef, attributeName as CFString) else {
        continue
      }
      if let title = stringAttribute(window, kAXTitleAttribute as CFString), !title.isEmpty {
        titles.append(title)
      }
      guard titleMatchesDeviceName(window, deviceName) else {
        continue
      }
      if let renderableView = renderableView(from: window) {
        windowsError = .success
        return renderableView
      }
    }

    // Retry kAXWindowsAttribute a few times. Simulator.app sometimes reports kAXErrorCannotComplete
    // briefly even though the window tree becomes queryable moments later.
    var lastWindowsError: AXError = .success
    for attempt in 0..<5 {
      var windowsRef: CFTypeRef?
      let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
      lastWindowsError = err
      if err == .success, let windows = windowsRef as? [AXUIElement] {
        for window in windows {
          if let title = stringAttribute(window, kAXTitleAttribute as CFString), !title.isEmpty {
            titles.append(title)
          }
          guard titleMatchesDeviceName(window, deviceName) else {
            continue
          }
          if let renderableView = renderableView(from: window) {
            windowsError = .success
            return renderableView
          }
        }
        break
      }
      usleep(useconds_t(100_000 * (attempt + 1)))
    }

    // Final fallback: walk the app's direct AX descendants and look for a descendant whose
    // title/description matches the device window. This avoids relying on kAXWindowsAttribute.
    if let renderableView = firstDescendantMatchingDeviceWindow(from: appRef, deviceName: deviceName, depthRemaining: 4) {
      windowsError = .success
      return renderableView
    }

    windowsError = lastWindowsError
    return nil
  }

  private static func renderableViewFromSystemWide(deviceName: String?, simulatorPID: pid_t, windowTitles: inout [String]) -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var titles: [String] = []
    defer { windowTitles = titles }

    guard let focusedApp = elementAttribute(systemWide, kAXFocusedApplicationAttribute as CFString) else {
      return nil
    }

    var focusedPID: pid_t = 0
    AXUIElementGetPid(focusedApp, &focusedPID)
    guard focusedPID == simulatorPID else {
      return nil
    }

    for attributeName in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
      guard let window = elementAttribute(focusedApp, attributeName as CFString) else {
        continue
      }
      if let title = stringAttribute(window, kAXTitleAttribute as CFString), !title.isEmpty {
        titles.append(title)
      }
      if titleMatchesDeviceName(window, deviceName) {
        return renderableView(from: window)
      }
    }

    return firstDescendantMatchingDeviceWindow(from: focusedApp, deviceName: deviceName, depthRemaining: 4)
  }

  private static func firstDescendantMatchingDeviceWindow(from element: AXUIElement, deviceName: String?, depthRemaining: UInt) -> AXUIElement? {
    if titleMatchesDeviceName(element, deviceName), let renderableView = renderableView(from: element) {
      return renderableView
    }
    guard depthRemaining > 0 else {
      return nil
    }
    for child in mergedChildren(of: element) {
      if let renderableView = firstDescendantMatchingDeviceWindow(from: child, deviceName: deviceName, depthRemaining: depthRemaining - 1) {
        return renderableView
      }
    }
    return nil
  }

  private static func renderableView(from element: AXUIElement) -> AXUIElement? {
    // Use the merged child enumeration here too: in iOS 26 the SimDisplayRenderableView
    // itself may surface its iOS subtree via AXChildrenInNavigationOrder rather than
    // kAXChildrenAttribute, which would otherwise cause us to skip the renderable view
    // entirely and fall back to the lossy XPC path.
    for child in mergedChildren(of: element) {
      guard let role = stringAttribute(child, kAXRoleAttribute as CFString), role == NSAccessibility.Role.group.rawValue else {
        continue
      }
      // SimDisplayRenderableView typically has no description or a specific one.
      // It's the first group directly under the window that contains the iOS content.
      // We verify by checking it exposes children via any standard child attribute.
      if !mergedChildren(of: child).isEmpty {
        return child
      }
    }
    return nil
  }

  // MARK: - Child Enumeration

  // Some bridged iOS containers (notably the iOS 26 floating tab bar) return an empty
  // kAXChildrenAttribute even though their children show up under attributes like
  // AXChildrenInNavigationOrder, AXTabs, AXVisibleChildren, etc. Accessibility Inspector
  // surfaces those tabs because it falls back across these alternate attributes.
  // We mirror that behaviour by collecting children from every standard child-providing
  // attribute and deduplicating by AXUIElement value (CFEqual-based) while preserving
  // first-seen order, so kAXChildrenAttribute remains canonical when populated.
  private static let childProvidingAttributes: [CFString] = [
    kAXChildrenAttribute as CFString,
    "AXChildrenInNavigationOrder" as CFString,
    kAXTabsAttribute as CFString,
    kAXVisibleChildrenAttribute as CFString,
    kAXSelectedChildrenAttribute as CFString,
    kAXContentsAttribute as CFString,
  ]

  private static func mergedChildren(of element: AXUIElement) -> [AXUIElement] {
    var merged: [AXUIElement] = []
    let seen = NSMutableSet()
    for attribute in childProvidingAttributes {
      var value: CFTypeRef?
      let err = AXUIElementCopyAttributeValue(element, attribute, &value)
      guard err == .success, let children = value as? [AXUIElement] else {
        continue
      }
      for child in children {
        guard !seen.contains(child) else {
          continue
        }
        seen.add(child)
        merged.append(child)
      }
    }
    return merged
  }

  // MARK: - Serialization

  private static func flatArray(from element: AXUIElement, origin containerOrigin: CGPoint) -> [[String: Any]] {
    var results: [[String: Any]] = []
    flatRecurse(element, origin: containerOrigin, into: &results)
    return results
  }

  private static func flatRecurse(_ element: AXUIElement, origin containerOrigin: CGPoint, into results: inout [[String: Any]]) {
    results.append(dictionary(from: element, origin: containerOrigin))
    for child in mergedChildren(of: element) {
      flatRecurse(child, origin: containerOrigin, into: &results)
    }
  }

  private static func nestedDictionary(from element: AXUIElement, origin containerOrigin: CGPoint) -> [String: Any] {
    var dict = dictionary(from: element, origin: containerOrigin)
    dict["children"] = mergedChildren(of: element).map { nestedDictionary(from: $0, origin: containerOrigin) }
    return dict
  }

  private static func dictionary(from element: AXUIElement, origin containerOrigin: CGPoint) -> [String: Any] {
    var dict: [String: Any] = [:]

    // Position & size -> frame in simulator-relative coordinates
    let position = origin(of: element)
    let size = size(of: element)
    let frame = CGRect(x: position.x - containerOrigin.x, y: position.y - containerOrigin.y, width: size.width, height: size.height)

    dict[FBAXKeys.frame.rawValue] = NSStringFromRect(frame)
    dict[FBAXKeys.frameDict.rawValue] = [
      "x": frame.origin.x,
      "y": frame.origin.y,
      "width": frame.size.width,
      "height": frame.size.height,
    ]

    let role = stringAttribute(element, kAXRoleAttribute as CFString)
    dict[FBAXKeys.role.rawValue] = role ?? NSNull()

    var typeValue = role
    if let role, role.hasPrefix("AX") {
      typeValue = String(role.dropFirst(2))
    }
    dict[FBAXKeys.type.rawValue] = typeValue ?? NSNull()

    dict[FBAXKeys.label.rawValue] = stringAttribute(element, kAXDescriptionAttribute as CFString) ?? NSNull()
    dict[FBAXKeys.value.rawValue] = stringAttribute(element, kAXValueAttribute as CFString) ?? NSNull()
    dict[FBAXKeys.uniqueID.rawValue] = stringAttribute(element, "AXIdentifier" as CFString) ?? NSNull()
    dict[FBAXKeys.title.rawValue] = stringAttribute(element, kAXTitleAttribute as CFString) ?? NSNull()
    dict[FBAXKeys.help.rawValue] = stringAttribute(element, kAXHelpAttribute as CFString) ?? NSNull()
    dict[FBAXKeys.enabled.rawValue] = boolAttribute(element, "AXEnabled" as CFString) ?? true
    dict[FBAXKeys.roleDescription.rawValue] = stringAttribute(element, kAXRoleDescriptionAttribute as CFString) ?? NSNull()
    dict[FBAXKeys.subrole.rawValue] = stringAttribute(element, kAXSubroleAttribute as CFString) ?? NSNull()
    dict[FBAXKeys.contentRequired.rawValue] = false
    dict[FBAXKeys.pid.rawValue] = 0

    // Custom actions
    var actionsRef: CFArray?
    AXUIElementCopyActionNames(element, &actionsRef)
    let actions = (actionsRef as? [String]) ?? []
    var customActionNames: [String] = []
    for action in actions where !["AXPress", "AXCancel", "AXRaise", "AXShowMenu"].contains(action) {
      var descriptionRef: CFString?
      AXUIElementCopyActionDescription(element, action as CFString, &descriptionRef)
      customActionNames.append((descriptionRef as String?) ?? action)
    }
    dict[FBAXKeys.customActions.rawValue] = customActionNames

    // Simulator.app bridges iOS elements via AXPTranslator, so AXTraits may be
    // readable even through the C API. Fall back to NSNull when unavailable.
    var traitsRef: CFTypeRef?
    let traitsError = AXUIElementCopyAttributeValue(element, "AXTraits" as CFString, &traitsRef)
    if traitsError == .success, let traitsNumber = traitsRef as? NSNumber {
      dict[FBAXKeys.traits.rawValue] = AXExtractTraits(traitsNumber.uint64Value).sorted()
    } else {
      dict[FBAXKeys.traits.rawValue] = NSNull()
    }

    return dict
  }

  // MARK: - Attribute Helpers

  private static func origin(of element: AXUIElement) -> CGPoint {
    var positionRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
    guard err == .success, let positionRef, CFGetTypeID(positionRef) == AXValueGetTypeID() else {
      return .zero
    }
    var point = CGPoint.zero
    AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
    return point
  }

  private static func size(of element: AXUIElement) -> CGSize {
    var sizeRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
    guard err == .success, let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
      return .zero
    }
    var size = CGSize.zero
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
    return size
  }

  private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    var ref: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, attribute, &ref)
    guard err == .success, let ref, CFGetTypeID(ref) == CFStringGetTypeID() else {
      return nil
    }
    return (ref as! CFString) as String
  }

  private static func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
    var ref: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, attribute, &ref)
    guard err == .success, let ref, CFGetTypeID(ref) == CFBooleanGetTypeID() else {
      return nil
    }
    return CFBooleanGetValue((ref as! CFBoolean))
  }

  private static func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
    var ref: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, attribute, &ref)
    guard err == .success, let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
      return nil
    }
    return (ref as! AXUIElement)
  }

  private static func titleMatchesDeviceName(_ element: AXUIElement, _ deviceName: String?) -> Bool {
    guard let deviceName, !deviceName.isEmpty else {
      return true
    }
    if let title = stringAttribute(element, kAXTitleAttribute as CFString), title.contains(deviceName) {
      return true
    }
    if let label = stringAttribute(element, kAXDescriptionAttribute as CFString), label.contains(deviceName) {
      return true
    }
    return false
  }

  private static func cgWindowTitles(forPID pid: pid_t) -> [String] {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
      return []
    }
    return windows.compactMap { info in
      guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
        return nil
      }
      guard let name = info[kCGWindowName as String] as? String, !name.isEmpty else {
        return nil
      }
      return name
    }
  }

  private static func errorDescription(_ error: AXError) -> String {
    switch error {
    case .success: return "kAXErrorSuccess"
    case .failure: return "kAXErrorFailure"
    case .illegalArgument: return "kAXErrorIllegalArgument"
    case .invalidUIElement: return "kAXErrorInvalidUIElement"
    case .invalidUIElementObserver: return "kAXErrorInvalidUIElementObserver"
    case .cannotComplete: return "kAXErrorCannotComplete"
    case .attributeUnsupported: return "kAXErrorAttributeUnsupported"
    case .actionUnsupported: return "kAXErrorActionUnsupported"
    case .notificationUnsupported: return "kAXErrorNotificationUnsupported"
    case .notImplemented: return "kAXErrorNotImplemented"
    case .notificationAlreadyRegistered: return "kAXErrorNotificationAlreadyRegistered"
    case .notificationNotRegistered: return "kAXErrorNotificationNotRegistered"
    case .apiDisabled: return "kAXErrorAPIDisabled"
    case .noValue: return "kAXErrorNoValue"
    case .parameterizedAttributeUnsupported: return "kAXErrorParameterizedAttributeUnsupported"
    case .notEnoughPrecision: return "kAXErrorNotEnoughPrecision"
    @unknown default: return "AXError(\(error.rawValue))"
    }
  }
}
