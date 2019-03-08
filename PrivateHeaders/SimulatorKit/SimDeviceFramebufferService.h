/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSObject.h>

#import <SimulatorKit/SimDeviceIOPortConsumer-Protocol.h>
#import <SimulatorKit/SimDisplayDamageRectangleDelegate-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderableDelegate-Protocol.h>
#import <SimulatorKit/SimDisplayRotationAngleDelegate-Protocol.h>

@class NSMapTable, NSString, NSUUID, SimDevice;
@protocol OS_dispatch_queue;

@interface SimDeviceFramebufferService : NSObject <SimDeviceIOPortConsumer, SimDisplayDamageRectangleDelegate, SimDisplayIOSurfaceRenderableDelegate, SimDisplayRotationAngleDelegate>
{
    BOOL _consumerAttached;
    unsigned short _displayClass;
    SimDevice *_device;
    NSString *_consumerIdentifier;
    NSUUID *_consumerUUID;
    NSObject<OS_dispatch_queue> *_executionQueue;
    NSMapTable *_clientsToCallbackQueue;
}

+ (id)tvOutFramebufferServiceForDevice:(id)arg1 error:(id *)arg2;
+ (id)mainScreenFramebufferServiceForDevice:(id)arg1 error:(id *)arg2;
+ (id)portForDisplayClass:(unsigned short)arg1 io:(id)arg2;
@property (retain, nonatomic) NSMapTable *clientsToCallbackQueue;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *executionQueue;
@property (nonatomic, assign) unsigned short displayClass;
@property (retain, nonatomic) NSUUID *consumerUUID;
@property (nonatomic, copy) NSString *consumerIdentifier;
@property (nonatomic, assign) BOOL consumerAttached;
@property (nonatomic, weak) SimDevice *device;

- (void)didReceiveDamageRect:(struct CGRect)arg1;
- (void)didChangeIOSurface:(id)arg1;
- (void)didChangeDisplayAngle:(double)arg1;
- (void)requestDeviceDimensions:(struct CGSize)arg1 scaledDimensions:(struct CGSize)arg2;
- (void)resume;
- (void)_ON_EXECUTION_QUEUE_sendSetIOSurfaceToClients:(struct __IOSurface *)arg1;
- (void)unregisterClient:(id)arg1;
- (void)registerClient:(id)arg1 onQueue:(id)arg2;
- (void)invalidate;
- (void)dealloc;
- (id)initWithName:(id)arg1 displayClass:(unsigned short)arg2 device:(id)arg3;

// Remaining properties
@property (atomic, copy, readonly) NSString *debugDescription;

@end

