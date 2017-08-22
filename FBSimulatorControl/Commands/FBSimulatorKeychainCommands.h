/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

@protocol FBSimulatorKeychainCommands <NSObject>

/**
 Cleans the keychain of the Simulator.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)clearKeychainWithError:(NSError **)error;

@end

/**
 A Strategy for clearing the system keychain.
 This is useful if you wish to restore the Simulator to a state where there are no login credentials in the keychain.
 */
@interface FBSimulatorKeychainCommands : NSObject <FBSimulatorKeychainCommands, FBiOSTargetCommand>

@end


NS_ASSUME_NONNULL_END
