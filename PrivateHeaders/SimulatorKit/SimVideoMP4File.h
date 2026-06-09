/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/SimVideoFile.h>

@class NSMutableArray, NSMutableData, SimVideoQuicktimeFormat;

/**
 Removed from SimulatorKit as of Xcode 27 (CoreSimulator 1155.4): a legacy video-file writer backing SimDisplayVideoWriter. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimVideoMP4File : SimVideoFile
{
  BOOL _wroteHeader;
  SimVideoQuicktimeFormat *_qtFormat;
  unsigned long long _bytesWritten;
  NSMutableData *_mediaData;
  NSMutableArray *_mediaSizes;
  NSMutableArray *_mediaDecodeTimes;
  NSMutableArray *_mediaDurationTimes;
  NSMutableArray *_mediaPresentationTimes;
  NSMutableArray *_syncSampleNumbers;
}

+ (void)parameterSetsForFormatDescription:(const struct opaqueCMFormatDescription *)arg1 sequenceParameterSetData:(id *)arg2 pictureParameterSetData:(id *)arg3;
+ (BOOL)isSampleBufferIFrame:(struct opaqueCMSampleBuffer *)arg1;
@property (nonatomic, retain) NSMutableArray *syncSampleNumbers;
@property (nonatomic, retain) NSMutableArray *mediaPresentationTimes;
@property (nonatomic, retain) NSMutableArray *mediaDurationTimes;
@property (nonatomic, retain) NSMutableArray *mediaDecodeTimes;
@property (nonatomic, retain) NSMutableArray *mediaSizes;
@property (nonatomic, retain) NSMutableData *mediaData;
@property (nonatomic, assign) unsigned long long bytesWritten;
@property (nonatomic, assign) BOOL wroteHeader;
@property (nonatomic, retain) SimVideoQuicktimeFormat *qtFormat;

- (void)writeSampleBuffer:(struct opaqueCMSampleBuffer *)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (void)writeMovieWithMedia:(BOOL)arg1;
- (void)setTimeScale:(double)arg1;
- (void)closeFile;
- (id)initVideoFileForDispatchIO:(id)arg1 error:(id *)arg2;

@end
