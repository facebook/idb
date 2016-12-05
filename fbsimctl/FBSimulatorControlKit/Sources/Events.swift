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
  case Approve = "approve"
  case Boot = "boot"
  case ClearKeychain = "clear_keychain"
  case Config = "config"
  case Create = "create"
  case Delete = "delete"
  case Diagnose = "diagnose"
  case Diagnostic = "diagnostic"
  case Erase = "erase"
  case Failure = "failure"
  case Help = "help"
  case Install = "install"
  case KeyboardOverride = "keyboard_override"
  case Launch = "launch"
  case LaunchXCTest = "launch_xctest"
  case List = "list"
  case ListApps = "list_apps"
  case ListDeviceSets = "list_device_sets"
  case Listen = "listen"
  case Log = "log"
  case Open = "open"
  case Query = "query"
  case Record = "record"
  case Relaunch = "relaunch"
  case Search = "search"
  case ServiceInfo = "service_info"
  case SetLocation = "set_location"
  case Shutdown = "shutdown"
  case Signalled = "signalled"
  case StateChange = "state"
  case Tap = "tap"
  case Terminate = "terminate"
  case Uninstall = "uninstall"
  case Upload = "upload"
  case WatchdogOverride = "watchdog_override"
}

public enum EventType : String {
  case Started = "started"
  case Ended = "ended"
  case Discrete = "discrete"
}
