/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/CDStructures.h>
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>

@class NSString, NSUUID;

@interface _TtC12SimulatorKit26SimDisplayScreenshotWriter : NSObject
{
    // Error parsing type: , name: fileType
    // Error parsing type: , name: consumerUUID
    // Error parsing type: , name: consumerIdentifier
    // Error parsing type: , name: _io
    // Error parsing type: , name: _port
    // Error parsing type: , name: _queue
    // Error parsing type: , name: _ioSurface
}

- (id)init;
- (void)writeScreenshotAsyncWithDispatchIO:(id)arg1 completionQueue:(id)arg2 completion:(CDUnknownBlockType)arg3;
- (BOOL)writeScreenshotWithDispatchIO:(id)arg1 error:(id *)arg2;
- (void)dealloc;
- (id)initWithIo:(id)arg1 displayClass:(unsigned short)arg2 error:(NSError *)arg3;
- (id)initWithIo:(id)arg1 port:(id)arg2 fileType:(long long)arg3 error:(NSError *)arg4;
@property (nonatomic, assign) IOSurfaceRef _ioSurface;
@property (nonatomic, copy, readonly) NSString *consumerIdentifier;
@property (nonatomic, readonly) NSUUID *consumerUUID;
@property (nonatomic, readonly) long long fileType;

@end
