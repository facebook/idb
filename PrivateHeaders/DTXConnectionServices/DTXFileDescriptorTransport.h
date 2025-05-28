/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <DTXConnectionServices/DTXTransport.h>

@interface DTXFileDescriptorTransport : DTXTransport
{
    int _inFD;
    int _outFD;
    dispatch_queue_t _inputQueue;
    dispatch_queue_t _outputQueue;
    int _outputWaitKQ;
    dispatch_queue_t _inputSource;
    CDUnknownBlockType _disconnectBlock;
}

- (int)supportedDirections;
- (void)disconnect;
- (unsigned long long)transmit:(const void *)arg1 ofLength:(unsigned long long)arg2;
- (void)setupWithIncomingDescriptor:(int)arg1 outgoingDescriptor:(int)arg2 disconnectBlock:(CDUnknownBlockType)arg3;
- (int)_createWriteKQueue:(int)arg1;
- (id)_createReadSource:(int)arg1;
- (void)dealloc;
- (id)initWithIncomingFileDescriptor:(int)arg1 outgoingFileDescriptor:(int)arg2 disconnectBlock:(CDUnknownBlockType)arg3;
- (id)initWithIncomingFilePath:(id)arg1 outgoingFilePath:(id)arg2 error:(id *)arg3;
- (id)init;

@end
