/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/SimVideoFile.h>

@class NSMutableArray, NSMutableData, SimVideoQuicktimeFormat;

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
@property (retain, nonatomic) NSMutableArray *syncSampleNumbers;
@property (retain, nonatomic) NSMutableArray *mediaPresentationTimes;
@property (retain, nonatomic) NSMutableArray *mediaDurationTimes;
@property (retain, nonatomic) NSMutableArray *mediaDecodeTimes;
@property (retain, nonatomic) NSMutableArray *mediaSizes;
@property (retain, nonatomic) NSMutableData *mediaData;
@property (nonatomic, assign) unsigned long long bytesWritten;
@property (nonatomic, assign) BOOL wroteHeader;
@property (retain, nonatomic) SimVideoQuicktimeFormat *qtFormat;

- (void)writeSampleBuffer:(struct opaqueCMSampleBuffer *)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (void)writeMovieWithMedia:(BOOL)arg1;
- (void)setTimeScale:(double)arg1;
- (void)closeFile;
- (id)initVideoFileForDispatchIO:(id)arg1 error:(id *)arg2;

@end
