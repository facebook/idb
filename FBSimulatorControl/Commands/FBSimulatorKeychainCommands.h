/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

@protocol FBSimulatorKeychainCommands <NSObject>

/**
 Cleans the keychain of the Simulator.

 @return A future that resolves when the keychain has been cleared.
 */
- (FBFuture<NSNull *> *)clearKeychain;

@end

/**
 A Strategy for clearing the system keychain.
 This is useful if you wish to restore the Simulator to a state where there are no login credentials in the keychain.
 */
@interface FBSimulatorKeychainCommands : NSObject <FBSimulatorKeychainCommands, FBiOSTargetCommand>

@end


NS_ASSUME_NONNULL_END
