/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Convenience.h"

#import "FBSimulatorConfiguration.h"
#import "FBSimulatorInteraction+Setup.h"

@implementation FBSimulatorInteraction (Convenience)

- (instancetype)configureWith:(FBSimulatorConfiguration *)configuration
{
  if (configuration.locale) {
    [self setLocale:configuration.locale];
  }
  return [self setupKeyboard];
}

@end

@implementation FBSimulator (FBSimulatorInteraction)

- (FBSimulatorInteraction *)interact
{
  return [FBSimulatorInteraction withSimulator:self];
}

@end
