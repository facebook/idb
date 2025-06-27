/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDevice.h>

#import "FBSimulatorDeviceOrientationCommands.h"

#import "FBSimulator.h"
#import "SimulatorApp/Purple.h"
#import "CoreSimulator/SimDevice+GSEventsPrivate.h"

@interface FBSimulatorDeviceOrientationCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorDeviceOrientationCommands

#pragma mark Initializers

+ (nonnull instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

- (nonnull FBFuture<NSNull *> *)setDeviceOrientation:(FBSimulatorDeviceOrientation)deviceOrientation
{
  PurpleMessage *purpleMessage = malloc(sizeof(PurpleMessage));
  memset(purpleMessage, 0, sizeof(PurpleMessage));
  purpleMessage->header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
  purpleMessage->header.msgh_size = sizeof(PurpleMessage);
  purpleMessage->header.msgh_id = 0x7b;
  purpleMessage->message.field1 = 0x20032;
  purpleMessage->message.field9 = 0x4;
  purpleMessage->message.field10 = (unsigned int)deviceOrientation;
  return sendPurpleMessage(self.simulator.device, purpleMessage);
}

@end
