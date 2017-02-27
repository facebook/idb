/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <SimulatorKit/SimVideoMP4File.h>

@interface SimVideoFragmentedMP4File : SimVideoMP4File
{
    BOOL _firstFrame;
    unsigned long long _sequenceNumber;
}

@property (nonatomic, assign) unsigned long long sequenceNumber;
@property (nonatomic, assign) BOOL firstFrame;
- (void)writeSampleBuffer:(struct opaqueCMSampleBuffer *)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (void)writeMovieWithMedia:(BOOL)arg1;
- (id)initVideoFileForDispatchIO:(id)arg1 error:(id *)arg2;

@end
