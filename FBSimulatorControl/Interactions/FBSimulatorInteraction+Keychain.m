/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Keychain.h"

#import "FBSimulatorError.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBKeychainClearStrategy.h"

@implementation FBSimulatorInteraction (Keychain)

- (instancetype)clearKeychain
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBKeychainClearStrategy withSimulator:simulator] clearKeychainWithError:error];
  }];
}

@end
