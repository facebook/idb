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

public protocol FBBridgeServiceHandling {
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

/// The services the guest command line reaches, each reporting to stdout.
public struct FBBridgeServices: FBBridgeServiceHandling {
  private let deliveredNotificationsDirectory: String?
  private let deliveredNotificationsTimeout: TimeInterval

  /// A nil directory and a non-positive timeout select the delivered-notifications reader's defaults.
  public init(deliveredNotificationsDirectory: String? = nil, deliveredNotificationsTimeout: TimeInterval = 0) {
    self.deliveredNotificationsDirectory = deliveredNotificationsDirectory
    self.deliveredNotificationsTimeout = deliveredNotificationsTimeout
  }

  #if !os(tvOS)
  public func contacts(_ action: String) -> Int32 {
    Int32(FBContactsService.handleContactsAction(action: action))
  }

  public func health(_ action: String, bundleID: String?, typeIDs: [String]) -> Int32 {
    Int32(FBHealthSettingsService.handleHealthSettingsAction(action: action, bundleID: bundleID, typeIdentifiers: typeIDs))
  }

  public func deliveredNotifications(_ action: String, bundleID: String?) -> Int32 {
    FBDeliveredNotificationsService.handleAction(action, bundleID: bundleID, directory: deliveredNotificationsDirectory, timeout: deliveredNotificationsTimeout)
  }
  #endif

  public func dns(_ action: String, arguments: [String]) -> Int32 {
    Int32(FBDnsService.handleDnsAction(action: action, arguments: arguments))
  }

  public func dynamicStore(_ action: String, arguments: [String]) -> Int32 {
    Int32(FBDynamicStoreService.handleDynamicStoreAction(action: action, arguments: arguments))
  }

  public func photos(_ action: String) -> Int32 {
    Int32(FBPhotoLibraryService.handlePhotoLibraryAction(action: action))
  }

  public func notifications(_ action: String, bundleID: String?) -> Int32 {
    Int32(FBNotificationSettingsService.handleNotificationSettingsAction(action: action, bundleID: bundleID))
  }

  public func privacy(_ action: String, arguments: [String]) -> Int32 {
    FBPrivacyService.handleAction(action, arguments: arguments)
  }

  public func proxy(_ action: String, arguments: [String]) -> Int32 {
    Int32(FBProxyService.handleProxyAction(action: action, arguments: arguments))
  }

  public func accessibility(_ action: String, arguments: [String]) -> Int32 {
    FBAccessibilityService.handleAction(action, arguments: arguments) { data in
      let written = data.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, stdout) } == data.count
      // A `quiet` stream writes a line per event and runs until it is killed.
      return written && fputc(10, stdout) != EOF && fflush(stdout) == 0
    }
  }

  public func orientation(_ action: String, arguments: [String]) -> Int32 {
    FBOrientationService.run(action: action, arguments: arguments)
  }

  public func repl(_ socketPath: String?, libraryPath: String) -> Int32 {
    // The socket server and injected IDB API must use libRepl's one control connection.
    guard let handle = dlopen((libraryPath as NSString).fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL) else {
      NSLog("Failed to load libRepl at %@: %@", libraryPath, Self.lastLoaderError())
      return 1
    }
    guard let symbol = dlsym(handle, "FBReplServeSocket") else {
      NSLog("libRepl is missing FBReplServeSocket: %@", Self.lastLoaderError())
      return 1
    }
    typealias Serve = @convention(c) (NSString?, NSArray, ObjCBool) -> Int32
    // The bridge exits when the session ends, so serve a single connection.
    return unsafeBitCast(symbol, to: Serve.self)(socketPath as NSString?, [] as NSArray, false)
  }

  private static func lastLoaderError() -> String {
    dlerror().map { String(cString: $0) } ?? "(null)"
  }
}

public enum FBBridgeCommand {
  private static let serviceNames = "contacts, dns, dynamic-store, photos, notifications, health, privacy, proxy, accessibility, orientation, repl"

  public static func run(arguments: [String], services: FBBridgeServiceHandling = FBBridgeServices()) -> Int32 {
    if let status = BridgeRPC.run(arguments: arguments) { return status }
    guard arguments.count >= 3 else {
      NSLog("Usage: %@ <service> <action> [args...]", arguments.first ?? "SimulatorFrameworkBridge")
      NSLog("Services: %@", serviceNames)
      NSLog("Actions: clear, approve, revoke, check, set, list, delivered, clear-delivered, snapshot, restore")
      return 1
    }
    return dispatch(service: arguments[1], action: arguments[2], arguments: Array(arguments.dropFirst(3)), services: services)
  }

  public static func dispatch(service: String, action: String, arguments: [String], services: FBBridgeServiceHandling = FBBridgeServices()) -> Int32 {
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
