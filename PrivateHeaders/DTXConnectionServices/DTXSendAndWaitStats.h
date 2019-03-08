/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSObject.h"

@class NSMutableSet, NSObject<OS_dispatch_queue>;

@interface DTXSendAndWaitStats : NSObject
{
    unsigned long long _totalSendBytes;
    unsigned long long _previousSendBytes;
    unsigned long long _lastStatTime;
    NSObject<OS_dispatch_queue> *_statsQueue;
    struct mach_timebase_info _timeBaseInfo;
    double _microsecondsPerUnit;
    unsigned long long _compressionTotalDataCompressed;
    unsigned long long _compressionTotalDataUncompressed;
    unsigned long long _compressionTotalNanosToCompress;
    NSMutableSet *_compressionTypeSet;
}

- (void)logStats:(id)arg1;
- (void)notifyCompressedData:(unsigned long long)arg1 withUncompressedSize:(unsigned long long)arg2 nanosToCompress:(unsigned long long)arg3 usingCompressionType:(int)arg4;
- (void)sentAdditionalBytes:(unsigned long long)arg1;
- (void)dealloc;
- (id)initWithQueue:(id)arg1 andMicrosPerUnit:(double)arg2;

@end

