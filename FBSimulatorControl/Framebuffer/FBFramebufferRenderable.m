/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferRenderable.h"

#import <CoreSimulator/SimDeviceIOClient.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderable-Protocol.h>
#import <SimulatorKit/SimDisplayRenderable-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayDescriptorState-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortConsumer-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortDescriptorState-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderable-Protocol.h>
#import <SimulatorKit/SimDisplayRenderable-Protocol.h>

@interface FBFramebufferRenderable ()

@property (nonatomic, strong, readonly) SimDeviceIOClient *ioClient;
@property (nonatomic, strong, readonly) id<SimDeviceIOPortInterface> port;
@property (nonatomic, strong, readonly) id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable> renderable;

@end

@implementation FBFramebufferRenderable

+ (instancetype)mainScreenRenderableForClient:(SimDeviceIOClient *)ioClient
{
  for (id<SimDeviceIOPortInterface> port in ioClient.ioPorts) {
    if (![port conformsToProtocol:@protocol(SimDeviceIOPortInterface)]) {
      continue;
    }
    id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable> renderable = (id) [port descriptor];
    if (![renderable conformsToProtocol:@protocol(SimDisplayRenderable)]) {
      continue;
    }
    if (![renderable conformsToProtocol:@protocol(SimDisplayIOSurfaceRenderable)]) {
      continue;
    }
    return [[self alloc] initWithIOClient:ioClient port:port renderable:renderable];
  }
  return nil;
}

- (instancetype)initWithIOClient:(SimDeviceIOClient *)ioClient port:(id<SimDeviceIOPortInterface>)port renderable:(id<SimDisplayIOSurfaceRenderable, SimDisplayRenderable>)renderable
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _ioClient = ioClient;
  _port = port;
  _renderable = renderable;

  return self;
}

- (void)attachConsumer:(id<SimDisplayDamageRectangleDelegate, SimDisplayIOSurfaceRenderableDelegate, SimDeviceIOPortConsumer>)consumer
{
  // The Port *must* be retained, otherwise the delegate will not be notified of changes to the Damage Rect.
  // The Damage rect is essential for video encoding.
  [consumer didChangeIOSurface:self.renderable.ioSurface];
  // simctl in Xcode 8.2 does not send the damage rect immediately, which means video encoding will start on the first change to the frame.
  // However, we want to immedately start as soon as the surface is available. In this case we say the whole rect is damaged for it to be rendered.
  [consumer didReceiveDamageRect:self.fullDamageRect];
  // Actually register the consumer.
  [self.ioClient attachConsumer:consumer toPort:self.port];
}

- (void)detachConsumer:(id<SimDisplayDamageRectangleDelegate, SimDisplayIOSurfaceRenderableDelegate, SimDeviceIOPortConsumer>)consumer
{
  [self.ioClient detachConsumer:consumer fromPort:self.port];
}

- (CGRect)fullDamageRect
{
  CGSize size = self.renderable.displaySize;
  return CGRectMake(0, 0, size.width, size.height);
}

@end
