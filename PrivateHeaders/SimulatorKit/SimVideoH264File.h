/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/SimVideoFile.h>

@interface SimVideoH264File : SimVideoFile
{
}

+ (BOOL)isSampleBufferIFrame:(struct opaqueCMSampleBuffer *)arg1;
- (void)writeSampleBuffer:(struct opaqueCMSampleBuffer *)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;

@end
