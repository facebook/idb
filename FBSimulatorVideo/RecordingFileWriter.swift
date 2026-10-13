/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia

// MARK: - RecordingFileWriter

/// The file a recording is written to: the sink for its encoded samples and its chapter markers.
protocol RecordingFileWriter: EncodedSampleConsumer, TimedMetadataConsumer, Sendable {
  /// Whether the file can change frame size mid-recording and still play correctly. A recording into a file that
  /// cannot keeps the canvas of its first frame, and letterboxes a later screen of another shape into it.
  var carriesFrameSizeChanges: Bool { get }

  /// The presentation timestamp of the file's media time zero, or nil until the first sample was written.
  var startPresentationTime: CMTime? { get }

  /// Finalizes the file. Called once, after the encoder has flushed all pending frames.
  func finish() async throws
}
