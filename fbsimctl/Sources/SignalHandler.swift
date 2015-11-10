/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

class SignalHandler {
  let callback: String -> Void
  var sources: [dispatch_source_t] = []

  init(callback: String -> Void) {
    self.callback = callback
  }

  private func register() {
    let signalPairs: [(Int32, String)] = [
      (SIGTERM, "SIGTERM"),
      (SIGHUP, "SIGHUP"),
      (SIGINT, "SIGINT")
    ]
    self.sources = signalPairs.map { (signal, name) in
      let source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_SIGNAL,
        UInt(signal),
        0,
        dispatch_get_main_queue()
      )
      dispatch_source_set_event_handler(source) {
        self.callback(name)
      }
      dispatch_resume(source)
      return source
    }
  }

  private func unregister() {
    for source in self.sources {
      dispatch_source_cancel(source)
    }
  }
}

extension SignalHandler {
  static func runUntilSignalled() {
    var signalled = false
    let handler = SignalHandler { signalName in
      print("Signalled by \(signalName)")
      signalled = true
    }

    handler.register()
    NSRunLoop.currentRunLoop().spinRunLoopWithTimeout(DBL_MAX) { signalled }
    handler.unregister()
  }
}
