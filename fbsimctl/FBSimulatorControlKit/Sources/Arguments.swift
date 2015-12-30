/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

public extension Action {
  public static let HELP_STR = "help"
  public static let INTERACT = "interact"
  public static let LIST = "list"
  public static let BOOT = "boot"
  public static let SHUTDOWN = "shutdown"
}

public extension Configuration {
  public static let DEBUG_LOGGING_FLAG = "--debug-logging"
}
