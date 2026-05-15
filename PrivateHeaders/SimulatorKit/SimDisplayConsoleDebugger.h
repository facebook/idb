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
#import <SimulatorKit/SimDisplayRotationAngleDelegate-Protocol.h>

typedef void (^CDUnknownBlockType)(void);

@class NSString, NSUUID;
@protocol OS_dispatch_queue;

@interface SimDisplayConsoleDebugger : NSObject <SimDeviceIOPortConsumer, SimDisplayDamageRectangleDelegate, SimDisplayIOSurfaceRenderableDelegate, SimDisplayRotationAngleDelegate>
{
  CDUnknownBlockType _debugLoggingBlock;
  NSUUID *_consumerUUID;
  NSString *_consumerIdentifier;
  NSObject<OS_dispatch_queue> *_consoleQueue;
}

@property (nonatomic, retain) NSObject<OS_dispatch_queue> *consoleQueue;
@property (nonatomic, copy) NSString *consumerIdentifier;
@property (nonatomic, retain) NSUUID *consumerUUID;
@property (nonatomic, assign) CDUnknownBlockType debugLoggingBlock;

- (void)didReceiveDamageRect:(struct CGRect)arg1;
- (void)didChangeIOSurface:(id)arg1;
- (void)didChangeDisplayAngle:(double)arg1;
- (id)initWithDebugLoggingBlock:(CDUnknownBlockType)arg1;

// Remaining properties
@property (atomic, readonly, copy) NSString *debugDescription;

@end
