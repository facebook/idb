/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private enum BridgeService: String {
  case contacts
  case health
  case dns
  case dynamicStore = "dynamic-store"
  case photos
  case notifications
  case privacy
  case proxy
  case accessibility
  case orientation
  case repl
}

@objc public protocol FBBridgeServiceHandling: AnyObject {
  #if !os(tvOS)
  func contacts(_ action: String) -> Int32
  func health(_ action: String, bundleID: String?, typeIDs: [String]) -> Int32
  func deliveredNotifications(_ action: String, bundleID: String?) -> Int32
  #endif
  func dns(_ action: String, arguments: [String]) -> Int32
  func dynamicStore(_ action: String, arguments: [String]) -> Int32
  func photos(_ action: String) -> Int32
  func notifications(_ action: String, bundleID: String?) -> Int32
  func privacy(_ action: String, arguments: [String]) -> Int32
  func proxy(_ action: String, arguments: [String]) -> Int32
  func accessibility(_ action: String, arguments: [String]) -> Int32
  func orientation(_ action: String, arguments: [String]) -> Int32
  func repl(_ socketPath: String?, libraryPath: String) -> Int32
}

@objc public final class FBBridgeCommand: NSObject {
  private static let serviceNames = "contacts, dns, dynamic-store, photos, notifications, health, privacy, proxy, accessibility, orientation, repl"

  @objc public static func run(arguments: [String], services: FBBridgeServiceHandling) -> Int32 {
    guard arguments.count >= 3 else {
      NSLog("Usage: %@ <service> <action> [args...]", arguments.first ?? "SimulatorFrameworkBridge")
      NSLog("Services: %@", serviceNames)
      NSLog("Actions: clear, approve, revoke, check, set, list")
      return 1
    }
    return dispatch(service: arguments[1], action: arguments[2], arguments: Array(arguments.dropFirst(3)), services: services)
  }

  @objc public static func dispatch(service: String, action: String, arguments: [String], services: FBBridgeServiceHandling) -> Int32 {
    let selectedService = BridgeService(rawValue: service)
    switch selectedService {
    case .contacts, .health:
      #if os(tvOS)
      NSLog("The %@ service is not available in a tvOS guest", service)
      return 1
      #else
      if selectedService == .contacts {
        return services.contacts(action)
      }
      return services.health(action, bundleID: arguments.first, typeIDs: Array(arguments.dropFirst()))
      #endif
    case .dns: return services.dns(action, arguments: arguments)
    case .dynamicStore: return services.dynamicStore(action, arguments: arguments)
    case .photos: return services.photos(action)
    case .notifications:
      // `list` on this service means "list the apps' settings", so the delivered notifications of one app
      // are read and cleared with their own verbs.
      if action == "delivered" || action == "clear-delivered" {
        #if os(tvOS)
        NSLog("The notifications %@ action is not available in a tvOS guest", action)
        return 1
        #else
        return services.deliveredNotifications(action, bundleID: arguments.first)
        #endif
      }
      return services.notifications(action, bundleID: arguments.first)
    case .privacy: return services.privacy(action, arguments: arguments)
    case .proxy: return services.proxy(action, arguments: arguments)
    case .accessibility: return services.accessibility(action, arguments: arguments)
    case .orientation: return services.orientation(action, arguments: arguments)
    case .repl:
      guard action == "start" else {
        NSLog("Unknown repl action: %@", action)
        return 1
      }
      guard arguments.count > 1, !arguments[1].isEmpty else {
        NSLog("repl start requires the libRepl path as its second argument")
        return 1
      }
      return services.repl(arguments.first, libraryPath: arguments[1])
    case nil:
      NSLog("Unknown service: %@", service)
      NSLog("Available services: %@", serviceNames)
      return 1
    }
  }
}
