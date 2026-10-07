/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A target that can record and stream its screen. The nouns live here rather than on `Target` so
/// that a target can be given them from a module of its own, additively, without the module
/// declaring the target's `Target` conformance having to see the video implementation.
public protocol VideoTarget: Target {

  associatedtype VideoRecording: VideoRecordingCommands
  var videoRecording: VideoRecording { get }

  associatedtype VideoStream: VideoStreamCommands
  var videoStream: VideoStream { get }
}
