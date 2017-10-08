/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "NSObject.h"

#import "DTXBlockCompressor.h"

@class NSString;

@interface DTXBlockCompressorLibCompression : NSObject <DTXBlockCompressor>
{
    void *_lzfseScratchBuffer;
    void *_lz4ScratchBuffer;
}

- (_Bool)uncompressBuffer:(const char *)arg1 ofLength:(unsigned long long)arg2 toBuffer:(char *)arg3 withKnownUncompressedLength:(unsigned long long)arg4 usingCompressionType:(int)arg5;
- (unsigned long long)compressBuffer:(const char *)arg1 ofLength:(unsigned long long)arg2 toBuffer:(char *)arg3 ofLength:(unsigned long long)arg4 usingCompressionType:(int)arg5 withFinalCompressionType:(int *)arg6;
- (void)dealloc;

// Remaining properties
@property(readonly, copy) NSString *debugDescription;
@property(readonly, copy) NSString *description;
@property(readonly) unsigned long long hash;
@property(readonly) Class superclass;

@end

