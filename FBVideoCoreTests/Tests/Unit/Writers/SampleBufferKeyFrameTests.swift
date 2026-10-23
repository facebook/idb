/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
@testable import FBVideoCore
import Foundation
import Testing

/// Which encoded samples the writers treat as keyframes, which they need before they can write a file.
@Suite
final class SampleBufferKeyFrameTests {

  private let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).webm")

  deinit {
    try? FileManager.default.removeItem(at: fileURL)
  }

  /// Sets `NotSync` on the sample the way an encoder reports it: `true` for a delta frame, `false` for a keyframe
  /// that says so explicitly, and nothing for a keyframe that does not.
  private func sample(notSync: Bool?) -> CMSampleBuffer {
    let sample = makeH264SampleBuffer(isKeyFrame: true)
    guard let notSync else {
      return sample
    }
    let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)!
    let attachments = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, 0), to: CFMutableDictionary.self)
    CFDictionarySetValue(
      attachments,
      Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
      Unmanaged.passUnretained(notSync ? kCFBooleanTrue : kCFBooleanFalse).toOpaque())
    return sample
  }

  @Test
  func aSampleWithoutNotSyncIsAKeyFrame() {
    #expect(sample(notSync: nil).isKeyFrame)
  }

  @Test
  func aSampleWhoseNotSyncIsFalseIsAKeyFrame() {
    #expect(sample(notSync: false).isKeyFrame)
  }

  @Test
  func aSampleWhoseNotSyncIsTrueIsNotAKeyFrame() {
    #expect(!sample(notSync: true).isKeyFrame)
  }

  /// The software HEVC encoder reports its keyframe as `NotSync = false`; a file that took that for a delta frame
  /// would wait for a keyframe that never comes and write nothing.
  @Test
  func theWebMWriterOpensItsFileOnAKeyFrameThatSaysNotSyncIsFalse() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    #expect(try writer.write(sample(notSync: false)))
    #expect(try writer.write(makeH264SampleBuffer(isKeyFrame: false, pts90k: 2970)))
    try writer.finish()
    #expect(writer.startPresentationTime != nil)
    #expect(try Data(contentsOf: fileURL).count > 0)
  }
}
