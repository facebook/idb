/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBControlCore
import FBSimulatorControl

public typealias EventName = FBiOSTargetActionType

extension EventName {
  static var approve = EventName(rawValue: "approve")
  static var clearKeychain = EventName(rawValue: "clear_keychain")
  static var config = EventName(rawValue: "config")
  static var create = EventName(rawValue: "create")
  static var delete = EventName(rawValue: "delete")
  static var diagnose = EventName(rawValue: "diagnose")
  static var diagnostic = EventName(rawValue: "diagnostic")
  static var focus = EventName(rawValue: "focus")
  static var erase = EventName(rawValue: "erase")
  static var failure = EventName(rawValue: "failure")
  static var help = EventName(rawValue: "help")
  static var install = EventName(rawValue: "install")
  static var keyboardOverride = EventName(rawValue: "keyboard_override")
  static var launch = EventName(rawValue: "launch")
  static var launchXCTest = EventName(rawValue: "launch_xctest")
  static var list = EventName(rawValue: "list")
  static var listApps = EventName(rawValue: "list_apps")
  static var listDeviceSets = EventName(rawValue: "list_device_sets")
  static var listen = EventName(rawValue: "listen")
  static var log = EventName(rawValue: "log")
  static var open = EventName(rawValue: "open")
  static var query = EventName(rawValue: "query")
  static var record = EventName(rawValue: "record")
  static var relaunch = EventName(rawValue: "relaunch")
  static var search = EventName(rawValue: "search")
  static var serviceInfo = EventName(rawValue: "service_info")
  static var setLocation = EventName(rawValue: "set_location")
  static var shutdown = EventName(rawValue: "shutdown")
  static var signalled = EventName(rawValue: "signalled")
  static var stateChange = EventName(rawValue: "state")
  static var stream = EventName(rawValue: "stream")
  static var tap = EventName(rawValue: "tap")
  static var terminate = EventName(rawValue: "terminate")
  static var uninstall = EventName(rawValue: "uninstall")
  static var upload = EventName(rawValue: "upload")
  static var waitingForDebugger = EventName(rawValue: "waiting_for_debugger")
  static var watchdogOverride = EventName(rawValue: "watchdog_override")
}

public enum EventType : String {
  case started = "started"
  case ended = "ended"
  case discrete = "discrete"
}
