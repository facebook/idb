/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorKeychainCommands.h"

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorKeychainCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorKeychainCommands

+ (instancetype)commandsWithTarget:(FBSimulator *)target
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

#pragma mark Public

- (FBFuture<NSNull *> *)clearKeychain
{
  return [FBFuture onQueue:self.simulator.workQueue resolveValue:^NSNull *(NSError **error) {
    if (![self.simulator.device resetKeychainWithError:error]) {
      return nil;
    }
    return NSNull.null;
  }];
}

@end
