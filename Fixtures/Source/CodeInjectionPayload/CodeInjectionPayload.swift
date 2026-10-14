/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import UIKit

// Entry points that FBSimulatorCodeInjection's smoke tests inject into a Simulator process. Each
// reads something only code running inside the process can know. The shim finds them by C symbol
// with `dlsym`, which is why they are `@_cdecl`, calls them on its own thread with no arguments, and
// frees the C string they return.

private func returning(_ string: String) -> UnsafeMutablePointer<CChar>? {
  strdup(string)
}

/// The Simulator the process runs in, as the process itself sees it, then its bundle identifier
/// (empty for a process that is not an app).
// patternlint-disable-next-line cdecl-unsupported
@_cdecl("CodeInjectionPayloadDescribeProcess")
public func describeProcess() -> UnsafeMutablePointer<CChar>? {
  let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? ""
  return returning("\(udid) \(Bundle.main.bundleIdentifier ?? "")")
}

/// How many views the app's windows hold right now, read on the main thread as UIKit requires.
// patternlint-disable-next-line cdecl-unsupported
@_cdecl("CodeInjectionPayloadCountViews")
public func countViews() -> UnsafeMutablePointer<CChar>? {
  let count = DispatchQueue.main.sync {
    // patternlint-disable-next-line swift-mainactor-assumeisolated
    MainActor.assumeIsolated {
      UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .reduce(0) { $0 + viewCount(in: $1) }
    }
  }
  return returning(String(count))
}

@MainActor
private func viewCount(in view: UIView) -> Int {
  view.subviews.reduce(1) { $0 + viewCount(in: $1) }
}

private final class InjectionCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  func increment() -> Int {
    lock.withLock {
      count += 1
      return count
    }
  }
}

private let injections = InjectionCounter()

/// How many times this entry point has run in the process, so a later session can see state an
/// earlier one left behind.
// patternlint-disable-next-line cdecl-unsupported
@_cdecl("CodeInjectionPayloadCountInjections")
public func countInjections() -> UnsafeMutablePointer<CChar>? {
  returning(String(injections.increment()))
}
