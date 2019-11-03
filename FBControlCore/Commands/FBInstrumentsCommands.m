/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBInstrumentsCommands.h"

#import "FBInstrumentsConfiguration.h"
#import "FBInstrumentsOperation.h"
#import "FBiOSTarget.h"

@implementation FBInstrumentsCommands

#pragma mark Properties

+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target
{
  return [[self alloc] initWithTarget:target];
}

- (instancetype)initWithTarget:(id<FBiOSTarget>)target
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;

  return self;
}

#pragma mark FBInstrumentsCommands

- (FBFuture<FBInstrumentsOperation *> *)startInstruments:(FBInstrumentsConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  return [FBInstrumentsOperation operationWithTarget:self.target configuration:configuration logger:logger];
}

@end
