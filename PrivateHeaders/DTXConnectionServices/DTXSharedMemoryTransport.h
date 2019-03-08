/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <DTXConnectionServices/DTXTransport.h>

@class NSObject<OS_dispatch_queue>;

@interface DTXSharedMemoryTransport : DTXTransport
{
    struct DTXSharedMemory *_shm;
    NSObject<OS_dispatch_queue> *_listenQueue;
    BOOL _creator;
}

+ (id)addressForMemory:(unsigned long long)arg1 inProcess:(int)arg2;
+ (id)addressForPosixSharedMemoryWithName:(id)arg1;
+ (id)schemes;
@property(readonly, nonatomic) struct DTXSharedMemory *sharedMemory; // @synthesize sharedMemory=_shm;
- (id)permittedBlockCompressionTypes;
- (id)localAddresses;
- (void)disconnect;
- (unsigned long long)transmit:(const void *)arg1 ofLength:(unsigned long long)arg2;
@property(nonatomic) int remotePid;
- (void)dealloc;
- (id)initWithMappedMemory:(struct DTXSharedMemory *)arg1;
- (id)initWithMemoryAddress:(unsigned long long)arg1 inTask:(unsigned int)arg2;
- (id)initWithRemoteAddress:(id)arg1;
- (id)initWithLocalName:(id)arg1 size:(int)arg2;
- (id)initWithLocalAddress:(id)arg1;
- (BOOL)_setupCreatingSharedMemory:(id)arg1 size:(int)arg2;
- (BOOL)_setupWithShm:(struct DTXSharedMemory *)arg1 asCreator:(BOOL)arg2;
@property(readonly, nonatomic) unsigned long long totalSharedMemorySize;

@end

