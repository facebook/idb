/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBBridgeServiceHandling: AnyObject {
  #if !os(tvOS)
  func contacts(_ action: String) -> Int32
  func health(_ action: String, bundleID: String?, typeIDs: [String]) -> Int32
  #endif
  func dns(_ action: String, arguments: [String]) -> Int32
  func dynamicStore(_ action: String, arguments: [String]) -> Int32
  func photos(_ action: String) -> Int32
  func notifications(_ action: String, bundleID: String?) -> Int32
  func proxy(_ action: String, arguments: [String]) -> Int32
  func accessibility(_ action: String, arguments: [String]) -> Int32
  func repl(_ socketPath: String?, libraryPath: String) -> Int32
}

@objc public final class FBBridgeCommand: NSObject {
  private static let serviceNames = "contacts, dns, dynamic-store, photos, notifications, health, proxy, accessibility, repl"

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
    switch service {
    case "contacts", "health":
      #if os(tvOS)
      NSLog("The %@ service is not available in a tvOS guest", service)
      return 1
      #else
      if service == "contacts" {
        return services.contacts(action)
      }
      return services.health(action, bundleID: arguments.first, typeIDs: Array(arguments.dropFirst()))
      #endif
    case "dns": return services.dns(action, arguments: arguments)
    case "dynamic-store": return services.dynamicStore(action, arguments: arguments)
    case "photos": return services.photos(action)
    case "notifications": return services.notifications(action, bundleID: arguments.first)
    case "proxy": return services.proxy(action, arguments: arguments)
    case "accessibility": return services.accessibility(action, arguments: arguments)
    case "repl":
      guard action == "start" else {
        NSLog("Unknown repl action: %@", action)
        return 1
      }
      guard arguments.count > 1, !arguments[1].isEmpty else {
        NSLog("repl start requires the libRepl path as its second argument")
        return 1
      }
      return services.repl(arguments.first, libraryPath: arguments[1])
    default:
      NSLog("Unknown service: %@", service)
      NSLog("Available services: %@", serviceNames)
      return 1
    }
  }
}
