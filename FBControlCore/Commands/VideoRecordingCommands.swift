/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol VideoRecordingCommands: AnyObject {

  func startRecording(toFile filePath: String) async throws -> any FBiOSTargetOperation

  func stopRecording() async throws
}
