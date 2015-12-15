/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSession.h"
#import "FBSimulatorSession+Private.h"

#import <objc/runtime.h>

#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventRelay.h"
#import "FBSimulatorHistory+Private.h"
#import "FBSimulatorHistory.h"
#import "FBSimulatorInteraction.h"
#import "FBSimulatorLogs.h"
#import "FBSimulatorNotificationEventSink.h"

NSString *const FBSimulatorSessionDidStartNotification = @"FBSimulatorSessionDidStartNotification";
NSString *const FBSimulatorSessionDidEndNotification = @"FBSimulatorSessionDidEndNotification";

@implementation FBSimulatorSession_NotStarted

- (FBSimulatorInteraction *)interact
{
  object_setClass(self, FBSimulatorSession_Started.class);
  [self fireNotificationNamed:FBSimulatorSessionDidStartNotification];
  return [self interact];
}

- (BOOL)terminateWithError:(NSError **)error
{
  return [FBSimulatorError failBoolWithErrorMessage:@"Cannot Terminate an session that hasn't started" errorOut:error];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Session (Not Started): Simulator %@",
    self.simulator
  ];
}

- (FBSimulatorSessionState)state
{
  return FBSimulatorSessionStateNotStarted;
}

@end

@implementation FBSimulatorSession_Started

- (FBSimulatorInteraction *)interact
{
  return [FBSimulatorInteraction withSimulator:self.simulator];
}

- (BOOL)terminateWithError:(NSError **)error
{
  object_setClass(self, FBSimulatorSession_Ended.class);
  BOOL result = [self.simulator freeFromPoolWithError:error];
  [self fireNotificationNamed:FBSimulatorSessionDidEndNotification];
  return result;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Session (Started): Simulator %@",
    self.simulator
  ];
}

- (FBSimulatorSessionState)state
{
  return FBSimulatorSessionStateStarted;
}

@end

@implementation FBSimulatorSession_Ended

- (BOOL)terminateWithError:(NSError **)error
{
  return [FBSimulatorError failBoolWithErrorMessage:@"Cannot Terminate an already Ended session" errorOut:error];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Session (Ended): Simulator %@",
    self.simulator
  ];
}

- (FBSimulatorSessionState)state
{
  return FBSimulatorSessionStateEnded;
}

@end

@implementation FBSimulatorSession

#pragma mark - Initializers

+ (instancetype)sessionWithSimulator:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);

  FBSimulatorSession *session = [[FBSimulatorSession_NotStarted alloc] initWithSimulator:simulator];
  simulator.session = session;
  return session;
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }


  _simulator = simulator;
  _uuid = NSUUID.UUID;

  return self;
}

#pragma mark - Public Interface

- (FBSimulatorHistory *)history
{
  return self.simulator.history;
}

- (FBSimulatorInteraction *)interact
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (BOOL)terminateWithError:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

#pragma mark Private

- (void)fireNotificationNamed:(NSString *)name
{
  [NSNotificationCenter.defaultCenter postNotificationName:name object:self];
}

@end
