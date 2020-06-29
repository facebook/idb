/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorAccessibilityCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorBridge.h"

@interface FBSimulatorAccessibilityCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorAccessibilityCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)targets
{
  return [[self alloc] initWithSimulator:targets];
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

#pragma mark FBSimulatorAccessibilityCommands Protocol Implementation

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityElements
{
  return [[self.simulator
    connectToBridge]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorBridge *bridge) {
      return [bridge accessibilityElements];
    }];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityElementAtPoint:(CGPoint)point
{
  return [[self.simulator
    connectToBridge]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorBridge *bridge) {
      return [bridge accessibilityElementAtPoint:point];
    }];
}

@end
