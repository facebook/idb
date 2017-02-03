/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <objc/NSObject.h>

#import <SimulatorKit/CDStructures.h>

@protocol OS_dispatch_queue;

/**
 Removed in Xcode 8.1
 */
@interface SimDeviceFramebufferBackingStore : NSObject
{
    unsigned int _port;
    unsigned long long _pixelsWide;
    unsigned long long _pixelsHigh;
    unsigned long long _rowByteSize;
    unsigned long long _size;
    struct __IOSurface *_ioSurface;
    NSObject<OS_dispatch_queue> *_imageDataAccessQueue;
    void *_data;
}

+ (id)allocateNewBackingStoreWithWidth:(unsigned long long)arg1 height:(unsigned long long)arg2 error:(id *)arg3;
@property (nonatomic) void *data;
@property (nonatomic) unsigned int port;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *imageDataAccessQueue;
@property(nonatomic, assign) struct __IOSurface *ioSurface; // @synthesize ioSurface=_ioSurface;
@property (nonatomic) unsigned long long size;
@property (nonatomic) unsigned long long rowByteSize;
@property(nonatomic, assign) unsigned long long pixelsHigh; // @synthesize pixelsHigh=_pixelsHigh;
@property(nonatomic, assign) unsigned long long pixelsWide; // @synthesize pixelsWide=_pixelsWide;
@property(readonly, nonatomic) struct CGImage *image;
- (void)flushDamageRegion:(struct CGRect)arg1;
- (void)flushEntireLiveBuffer;
- (void)accessBackingStoreDuring:(CDUnknownBlockType)arg1;
- (void)dealloc;
- (void)invalidate;
- (id)initWithData:(void *)arg1 port:(unsigned int)arg2 size:(unsigned long long)arg3 rowByteSize:(unsigned long long)arg4 pixelsWide:(unsigned long long)arg5 pixelsHigh:(unsigned long long)arg6;

@end

