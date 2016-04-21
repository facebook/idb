/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

struct SignalInfo : JSONDescribeable, CustomStringConvertible {
  let signo: Int32
  let name: String

  var jsonDescription: JSON {
    get {
      return JSON.JDictionary([
        "signo" : JSON.JNumber(NSNumber(int: self.signo)),
        "name" : JSON.JString(self.name),
      ])
    }
  }

  var description: String {
    get {
      return "\(self.name) \(self.signo)"
    }
  }
}

let signalPairs: [SignalInfo] = [
  SignalInfo(signo: SIGTERM, name: "SIGTERM"),
  SignalInfo(signo: SIGHUP, name: "SIGHUP"),
  SignalInfo(signo: SIGINT, name: "SIGINT")
]

func ignoreSignal(_: Int32) {}

class SignalHandler {
  let callback: SignalInfo -> Void
  var sources: [dispatch_source_t] = []

  init(callback: SignalInfo -> Void) {
    self.callback = callback
  }

  func register() {
    self.sources = signalPairs.map { info in
      signal(info.signo, ignoreSignal)
      let source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_SIGNAL,
        UInt(info.signo),
        0,
        dispatch_get_main_queue()
      )
      dispatch_source_set_event_handler(source) {
        self.callback(info)
      }
      dispatch_resume(source)
      return source
    }
  }

  func unregister() {
    for source in self.sources {
      dispatch_source_cancel(source)
    }
  }
}
