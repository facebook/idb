/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBProcessInfo;
@class FBSimulator;

/**
 Protocol for interacting with a Simulator's launchctl
 */
@protocol FBSimulatorLaunchCtlCommandsProtocol <NSObject, FBiOSTargetCommand>

#pragma mark Querying Services

- (nonnull FBFuture<NSString *> *)serviceNameForProcessIdentifier:(pid_t)pid;
- (nonnull FBFuture<NSString *> *)serviceNameForProcess:(nonnull FBProcessInfo *)process;
- (nonnull FBFuture<NSDictionary<NSString *, NSNumber *> *> *)serviceNamesAndProcessIdentifiersMatching:(nonnull NSRegularExpression *)regex;
- (nonnull FBFuture<NSArray<id> *> *)firstServiceNameAndProcessIdentifierMatching:(nonnull NSRegularExpression *)regex;
- (nonnull FBFuture<NSNumber *> *)processIsRunningOnSimulator:(nonnull FBProcessInfo *)process;
- (nonnull FBFuture<NSDictionary<NSString *, id> *> *)listServices;

#pragma mark Manipulating Services

- (nonnull FBFuture<NSString *> *)stopServiceWithName:(nonnull NSString *)serviceName;
- (nonnull FBFuture<NSString *> *)startServiceWithName:(nonnull NSString *)serviceName;

@end

// FBSimulatorLaunchCtlCommands class is now implemented in Swift.
// The Swift header is imported by the umbrella header FBSimulatorControl.h.
