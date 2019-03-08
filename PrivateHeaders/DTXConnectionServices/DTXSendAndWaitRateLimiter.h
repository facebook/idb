/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSObject.h"

#import "DTXRateLimiter.h"

@class DTXSendAndWaitStats, NSObject<OS_dispatch_queue>, NSObject<OS_dispatch_source>, NSString;

@interface DTXSendAndWaitRateLimiter : NSObject <DTXRateLimiter>
{
    NSObject<OS_dispatch_queue> *_actionQueue;
    double _microsecondsPerUnit;
    struct mach_timebase_info _timeBaseInfo;
    _Bool _logSends;
    NSObject<OS_dispatch_queue> *_statsQueue;
    NSObject<OS_dispatch_source> *_timer;
    DTXSendAndWaitStats *_stats;
}

- (void)notifyCompressedData:(unsigned long long)arg1 withUncompressedSize:(unsigned long long)arg2 nanosToCompress:(unsigned long long)arg3 usingCompressionType:(int)arg4;
- (void)spendUnits:(unsigned long long)arg1 onAction:(CDUnknownBlockType)arg2;
- (void)dealloc;
- (id)initWithUnitsPerSecond:(unsigned long long)arg1;

// Remaining properties
@property(readonly, copy) NSString *debugDescription;
@property(readonly, copy) NSString *description;
@property(readonly) unsigned long long hash;
@property(readonly) Class superclass;

@end

