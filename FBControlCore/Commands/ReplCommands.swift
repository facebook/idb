/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol ReplCommands: AnyObject {

  func startReplTest(bundlePath: String) async throws -> ReplSession

  func startReplSimulator() async throws -> ReplSession

  func startReplApp(bundleID: String) async throws -> ReplSession
}
