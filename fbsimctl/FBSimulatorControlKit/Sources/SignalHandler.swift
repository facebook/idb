/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

struct SignalInfo : EventReporterSubject {
  let signo: Int32
  let name: String

  var jsonDescription: JSON { get {
    return JSON.dictionary([
      "signo" : JSON.number(NSNumber(value: self.signo as Int32)),
      "name" : JSON.string(self.name),
    ])
  }}

  var description: String { get {
    return "\(self.name) \(self.signo)"
  }}
}

let signalPairs: [SignalInfo] = [
  SignalInfo(signo: SIGTERM, name: "SIGTERM"),
  SignalInfo(signo: SIGHUP, name: "SIGHUP"),
  SignalInfo(signo: SIGINT, name: "SIGINT")
]

func ignoreSignal(_: Int32) {}

class SignalHandler {
  let callback: (SignalInfo) -> Void
  var sources: [DispatchSource] = []

  init(callback: @escaping (SignalInfo) -> Void) {
    self.callback = callback
  }

  func register() {
    self.sources = signalPairs.map { info in
      signal(info.signo, ignoreSignal)
      let source = DispatchSource.makeSignalSource(signal: info.signo, queue: DispatchQueue.main)
      source.setEventHandler {
        self.callback(info)
      }
      source.resume()
      return source as! DispatchSource
    }
  }

  func unregister() {
    for source in self.sources {
      source.cancel()
    }
  }
}
