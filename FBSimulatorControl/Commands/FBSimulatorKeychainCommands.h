// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBSimulator;

@protocol FBSimulatorKeychainCommandsProtocol <NSObject>

/**
 Cleans the keychain of the Simulator.

 @return A future that resolves when the keychain has been cleared.
 */
- (nonnull FBFuture<NSNull *> *)clearKeychain;

@end

// FBSimulatorKeychainCommands class is now implemented in Swift.
// The Swift header is imported by the umbrella header FBSimulatorControl.h.
