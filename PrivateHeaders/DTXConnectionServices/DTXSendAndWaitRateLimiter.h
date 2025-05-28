/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class DTXSendAndWaitStats;

@protocol DTXRateLimiter;

@interface DTXSendAndWaitRateLimiter : NSObject <DTXRateLimiter>
{
    dispatch_queue_t _actionQueue;
    double _microsecondsPerUnit;
    struct mach_timebase_info _timeBaseInfo;
    _Bool _logSends;
    dispatch_queue_t statsQueue;
    dispatch_source_t _timer;
    DTXSendAndWaitStats *_stats;
}

- (void)notifyCompressedData:(unsigned long long)arg1 withUncompressedSize:(unsigned long long)arg2 nanosToCompress:(unsigned long long)arg3 usingCompressionType:(int)arg4;
- (void)spendUnits:(unsigned long long)arg1 onAction:(CDUnknownBlockType)arg2;
- (void)dealloc;
- (id)initWithUnitsPerSecond:(unsigned long long)arg1;

// Remaining properties
@property(readonly, copy) NSString *debugDescription;




@end

