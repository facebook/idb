/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <SimulatorKit/CDStructures.h>
#import <SimulatorKit/SimDeviceIOPortConsumer-Protocol.h>
#import <SimulatorKit/SimDisplayDamageRectangleDelegate-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderableDelegate-Protocol.h>

@class MTLTextureDescriptor, NSString, NSUUID, SimVideoFile;
@protocol MTLCommandQueue, MTLComputePipelineState, MTLDevice, MTLFunction, MTLLibrary, OS_dispatch_io, OS_dispatch_queue;

@interface SimDisplayVideoWriter : NSObject <SimDeviceIOPortConsumer, SimDisplayDamageRectangleDelegate, SimDisplayIOSurfaceRenderableDelegate>
{
    BOOL _startedWriting;
    double _framesPerSecond;
    unsigned long long _timeScale;
    NSUUID *_consumerUUID;
    NSString *_consumerIdentifier;
    NSObject<OS_dispatch_queue> *_executionQueue;
    id<MTLDevice> _metalDevice;
    id<MTLLibrary> _metalLibrary;
    id<MTLCommandQueue> _metalCommandQueue;
    id<MTLFunction> _kernelFunction;
    id<MTLComputePipelineState> _pipelineState;
    struct __CVMetalTextureCache *_metalTextureCache;
    MTLTextureDescriptor *_ioSurfaceTextureDescriptor;
    NSObject<OS_dispatch_io> *_dispatch_io;
    SimVideoFile *_videoFile;
    id _ioSurface;
    struct OpaqueVTCompressionSession *_compressionSession;
    CDStruct_1b6d18a9 _startTime;
    CDStruct_1b6d18a9 _lastEncodeTime;
}

+ (id)videoWriterForURL:(id)arg1 fileType:(id)arg2 completionQueue:(id)arg3 completionHandler:( void(^)(NSError *) )arg4;
+ (id)videoWriterForDispatchIO:(id)arg1 fileType:(id)arg2 completionQueue:(id)arg3 completionHandler:( void(^)(NSError *) )arg4;
+ (id)videoWriter;
@property (nonatomic, assign) CDStruct_1b6d18a9 lastEncodeTime;
@property (nonatomic, assign) CDStruct_1b6d18a9 startTime;
@property (nonatomic, assign) struct OpaqueVTCompressionSession *compressionSession;
@property (retain, nonatomic) id ioSurface;
@property (nonatomic, assign) BOOL startedWriting;
@property (retain, nonatomic) SimVideoFile *videoFile;
@property (retain, nonatomic) NSObject<OS_dispatch_io> *dispatch_io;
@property (retain, nonatomic) MTLTextureDescriptor *ioSurfaceTextureDescriptor;
@property (nonatomic, assign) struct __CVMetalTextureCache *metalTextureCache;
@property (retain, nonatomic) id<MTLComputePipelineState> pipelineState;
@property (retain, nonatomic) id<MTLFunction> kernelFunction;
@property (retain, nonatomic) id<MTLCommandQueue> metalCommandQueue;
@property (retain, nonatomic) id<MTLLibrary> metalLibrary;
@property (retain, nonatomic) id<MTLDevice> metalDevice;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *executionQueue;
@property (nonatomic, copy) NSString *consumerIdentifier;
@property (retain, nonatomic) NSUUID *consumerUUID;
@property (nonatomic, assign) unsigned long long timeScale;
@property (nonatomic, assign) double framesPerSecond;

- (void)startWriting;
- (void)finishWriting;
- (void)didReceiveDamageRect:(struct CGRect)arg1;
- (void)didChangeIOSurface:(id)arg1;
- (void)dealloc;

// Remaining properties
@property (atomic, copy, readonly) NSString *debugDescription;

@end
