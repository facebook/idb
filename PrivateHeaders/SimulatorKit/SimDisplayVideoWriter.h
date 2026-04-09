/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <SimulatorKit/SimDeviceIOPortConsumer-Protocol.h>
#import <SimulatorKit/SimDisplayDamageRectangleDelegate-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderableDelegate-Protocol.h>

@class MTLTextureDescriptor, NSString, NSUUID, SimVideoFile;
@protocol MTLCommandQueue, MTLComputePipelineState, MTLDevice, MTLFunction, MTLLibrary, OS_dispatch_io, OS_dispatch_queue;

typedef struct {
  unsigned long long _field1;
  void *_field2;
  unsigned long long *_field3;
  unsigned long long _field4[5];
} CDStruct_70511ce9;

typedef struct {
  long long value;
  int timescale;
  unsigned int flags;
  long long epoch;
} CDStruct_1b6d18a9;

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

+ (id)videoWriterForURL:(id)arg1 fileType:(id)arg2 completionQueue:(id)arg3 completionHandler:(void (^)(NSError *) )arg4;
+ (id)videoWriterForDispatchIO:(id)arg1 fileType:(id)arg2 completionQueue:(id)arg3 completionHandler:(void (^)(NSError *) )arg4;
+ (id)videoWriter;
@property (nonatomic, assign) CDStruct_1b6d18a9 lastEncodeTime;
@property (nonatomic, assign) CDStruct_1b6d18a9 startTime;
@property (nonatomic, assign) struct OpaqueVTCompressionSession *compressionSession;
@property (nonatomic, retain) id ioSurface;
@property (nonatomic, assign) BOOL startedWriting;
@property (nonatomic, retain) SimVideoFile *videoFile;
@property (nonatomic, retain) NSObject<OS_dispatch_io> *dispatch_io;
@property (nonatomic, retain) MTLTextureDescriptor *ioSurfaceTextureDescriptor;
@property (nonatomic, assign) struct __CVMetalTextureCache *metalTextureCache;
@property (nonatomic, retain) id<MTLComputePipelineState> pipelineState;
@property (nonatomic, retain) id<MTLFunction> kernelFunction;
@property (nonatomic, retain) id<MTLCommandQueue> metalCommandQueue;
@property (nonatomic, retain) id<MTLLibrary> metalLibrary;
@property (nonatomic, retain) id<MTLDevice> metalDevice;
@property (nonatomic, retain) NSObject<OS_dispatch_queue> *executionQueue;
@property (nonatomic, copy) NSString *consumerIdentifier;
@property (nonatomic, retain) NSUUID *consumerUUID;
@property (nonatomic, assign) unsigned long long timeScale;
@property (nonatomic, assign) double framesPerSecond;

- (void)startWriting;
- (void)finishWriting;
- (void)didReceiveDamageRect:(struct CGRect)arg1;
- (void)didChangeIOSurface:(id)arg1;
- (void)dealloc;

// Remaining properties
@property (atomic, readonly, copy) NSString *debugDescription;

@end
