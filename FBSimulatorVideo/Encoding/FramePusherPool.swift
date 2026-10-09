/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// Set-up frame pushers keyed by the source each was set up for, so a stream that switches between displays
/// takes one rather than starting an encoder on the switch.
struct FramePusherPool {
  private var pushers: [VideoFrameSource: any FramePusher] = [:]

  func contains(_ source: VideoFrameSource) -> Bool {
    pushers[source] != nil
  }

  mutating func take(_ source: VideoFrameSource) -> (any FramePusher)? {
    pushers.removeValue(forKey: source)
  }

  /// Returns the pusher already kept for `source`, which the caller tears down.
  mutating func keep(_ pusher: any FramePusher, for source: VideoFrameSource) -> (any FramePusher)? {
    pushers.updateValue(pusher, forKey: source)
  }

  mutating func removeAll() -> [any FramePusher] {
    defer { pushers = [:] }
    return Array(pushers.values)
  }
}
