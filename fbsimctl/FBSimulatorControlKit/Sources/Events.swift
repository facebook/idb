/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBSimulatorControl

public enum EventName : String {
  case approve = "approve"
  case boot = "boot"
  case clearKeychain = "clear_keychain"
  case config = "config"
  case create = "create"
  case delete = "delete"
  case diagnose = "diagnose"
  case diagnostic = "diagnostic"
  case focus = "focus"
  case erase = "erase"
  case failure = "failure"
  case help = "help"
  case hid = "hid"
  case install = "install"
  case keyboardOverride = "keyboard_override"
  case launch = "launch"
  case launchXCTest = "launch_xctest"
  case list = "list"
  case listApps = "list_apps"
  case listDeviceSets = "list_device_sets"
  case listen = "listen"
  case log = "log"
  case open = "open"
  case query = "query"
  case record = "record"
  case relaunch = "relaunch"
  case search = "search"
  case serviceInfo = "service_info"
  case setLocation = "set_location"
  case shutdown = "shutdown"
  case signalled = "signalled"
  case stateChange = "state"
  case stream = "stream"
  case tap = "tap"
  case terminate = "terminate"
  case uninstall = "uninstall"
  case upload = "upload"
  case waitingForDebugger = "waiting_for_debugger"
  case watchdogOverride = "watchdog_override"
}

public enum EventType : String {
  case started = "started"
  case ended = "ended"
  case discrete = "discrete"
}
