/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

