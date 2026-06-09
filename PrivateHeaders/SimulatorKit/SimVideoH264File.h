/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/SimVideoFile.h>

/**
 Removed from SimulatorKit as of Xcode 27 (CoreSimulator 1155.4): a legacy video-file writer backing SimDisplayVideoWriter. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimVideoH264File : SimVideoFile
{}

+ (BOOL)isSampleBufferIFrame:(struct opaqueCMSampleBuffer *)arg1;
- (void)writeSampleBuffer:(struct opaqueCMSampleBuffer *)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;

@end
