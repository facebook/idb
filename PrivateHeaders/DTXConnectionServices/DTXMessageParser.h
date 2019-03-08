/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSObject.h"

@class NSMutableDictionary, NSObject<OS_dispatch_queue>, NSObject<OS_dispatch_semaphore>;

@interface DTXMessageParser : NSObject
{
    const char *_parsingBuffer;
    unsigned long long _parsingBufferUsed;
    unsigned long long _parsingBufferSize;
    NSObject<OS_dispatch_queue> *_parsingQueue;
    NSMutableDictionary *_fragmentedBuffersByIdentifier;
    NSObject<OS_dispatch_semaphore> *_hasMoreDataSem;
    NSObject<OS_dispatch_semaphore> *_wantsMoreDataSem;
    unsigned long long _desiredSize;
    BOOL _eof;
    id <DTXBlockCompressor> _compressor;
}

- (void)replaceCompressor:(id)arg1;
- (void)parsingComplete;
- (void)parseIncomingBytes:(const char *)arg1 length:(unsigned long long)arg2;
- (const void *)waitForMoreData:(unsigned long long)arg1 incrementalBuffer:(const void **)arg2;
- (id)parseMessageWithExceptionHandler:(CDUnknownBlockType)arg1;
- (void)dealloc;
- (id)initWithMessageHandler:(CDUnknownBlockType)arg1 andParseExceptionHandler:(CDUnknownBlockType)arg2;

@end

