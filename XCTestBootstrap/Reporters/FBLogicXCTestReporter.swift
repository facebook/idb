/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBLogicXCTestReporter: NSObjectProtocol {

  @objc(processWaitingForDebuggerWithProcessIdentifier:)
  func processWaitingForDebugger(withProcessIdentifier pid: pid_t)

  @objc func didBeginExecutingTestPlan()

  @objc func didFinishExecutingTestPlan()

  @objc(testHadOutput:)
  func testHadOutput(_ output: String)

  @objc(handleEventJSONData:)
  func handleEventJSONData(_ data: Data)

  @objc(didCrashDuringTest:)
  func didCrashDuringTest(_ error: Error)
}
