/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

#if canImport(SimulatorFrameworkBridgeRuntime)
@_implementationOnly import SimulatorFrameworkBridgeRuntime
#endif
private let UNAuthorizationStatusNotDetermined: UInt = 0
private let UNAuthorizationStatusAuthorized: UInt = 2

private func printSectionJSON(bundleID: String, section: FBNotificationSection) -> Bool {
  // The existing C output stops the bundle identifier at its first NUL.
  let printedBundleID = String(bundleID.prefix { $0 != "\0" })
  guard section.isFound else {
    // patternlint-disable-next-line avoid-print-to-prevent-production-overhead
    print("{\"bundleID\":\"\(printedBundleID)\",\"found\":false}")
    return true
  }
  guard let values = try? section.readValues() else {
    return false
  }
  let allowed = values.allowsNotifications ? "true" : "false"
  let center = values.showsInNotificationCenter.map { $0.boolValue ? "true" : "false" } ?? "null"
  let lockScreen = values.showsInLockScreen.map { $0.boolValue ? "true" : "false" } ?? "null"
  // patternlint-disable-next-line avoid-print-to-prevent-production-overhead
  print("{\"bundleID\":\"\(printedBundleID)\",\"found\":true,\"allowsNotifications\":\(allowed),\"authorizationStatus\":\(values.authorizationStatus),\"showsInNotificationCenter\":\(center),\"showsInLockScreen\":\(lockScreen)}")
  return true
}

@objc public final class NotificationSettingsServiceStaticFuncs: NSObject {
  @objc(handleNotificationSettingsAction:bundleID:)
  public static func handleNotificationSettingsAction(action: String?, bundleID: String?) -> Int {
    guard let client = FBNotificationSettingsClient.live() else {
      return 1
    }
    return handleNotificationSettingsActionWithClient(action: action, bundleID: bundleID, client: client)
  }

  @objc(handleNotificationSettingsActionWithGateway:bundleID:gateway:)
  public static func handleNotificationSettingsActionWithGateway(action: String?, bundleID: String?, gateway: Any) -> Int {
    handleNotificationSettingsActionWithClient(action: action, bundleID: bundleID, client: FBNotificationSettingsClient(gateway: gateway))
  }
}

private func handleNotificationSettingsActionWithClient(
  action: String?,
  bundleID: String?,
  client: FBNotificationSettingsClient
) -> Int {
  do {
    if action == "check" || action == "list" {
      if let bundleID {
        let section = try client.section(forIdentifier: bundleID)
        guard printSectionJSON(bundleID: bundleID, section: section) else {
          return 1
        }
      } else {
        let identifiers = try client.allSectionIDs()
        for sectionID in identifiers {
          let section = try client.section(forIdentifier: sectionID)
          guard printSectionJSON(bundleID: sectionID, section: section) else {
            return 1
          }
        }
      }
      return 0
    }

    guard let bundleID else {
      NSLog("[NotificationSettings] bundleID required for %@", action ?? "(null)")
      return 1
    }

    var section = try client.section(forIdentifier: bundleID)
    if action == "approve" {
      if !section.isFound {
        section = try client.createSection(forIdentifier: bundleID)
        NSLog("[NotificationSettings] Created new section info for %@", bundleID)
      }
      try section.setAllowsNotifications(true)
      try section.setAuthorizationStatus(UNAuthorizationStatusAuthorized)
      try section.setAlertType(1)
      try section.setLockScreenSetting(1)
      try section.setNotificationCenterSetting(1)
      let absent = try section.setEffectiveVisibility(true)
      if !absent.isEmpty {
        NSLog(
          "[NotificationSettings] This runtime's BBSectionInfo has no %@, so %@ is authorized but may not retain its notifications",
          absent.joined(separator: " or "),
          bundleID
        )
      }
    } else if action == "revoke" {
      guard section.isFound else {
        NSLog("[NotificationSettings] No section info for %@, nothing to revoke.", bundleID)
        return 0
      }
      try section.setAllowsNotifications(false)
      try section.setAuthorizationStatus(UNAuthorizationStatusNotDetermined)
    } else {
      NSLog("[NotificationSettings] Unknown action: %@. Use approve, revoke, or check.", action ?? "(null)")
      return 1
    }

    try client.write(section, forIdentifier: bundleID)
    NSLog("[NotificationSettings] %@ notifications for %@", action ?? "(null)", bundleID)
    return 0
  } catch {
    return 1
  }
}
