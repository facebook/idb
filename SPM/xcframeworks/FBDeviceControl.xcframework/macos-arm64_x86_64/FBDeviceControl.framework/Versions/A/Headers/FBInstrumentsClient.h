/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBAMDServiceConnection;
@class FBApplicationLaunchConfiguration;

/**
 A client for Instruments.
 */
@interface FBInstrumentsClient : NSObject

#pragma mark Initializers

/**
 Constructs a transport for the specified service connection.

 @param connection the connection to use.
 @param logger the logger to use.
 @return a Future that resolves with the instruments client.
 */
+ (nonnull FBFuture<FBInstrumentsClient *> *)instrumentsClientWithServiceConnection:(nonnull FBAMDServiceConnection *)connection logger:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Launches an application.

 @param configuration the app launch configuration.
 @return a Future that resolves with the pid of the app once it has launched.
 */
- (nonnull FBFuture<NSNumber *> *)launchApplication:(nonnull FBApplicationLaunchConfiguration *)configuration;

/**
 Kills an application

 @param processIdentifier the pid of the process to kill.
 @return a Future that resolves when killed.
 */
- (nonnull FBFuture<NSNull *> *)killProcess:(pid_t)processIdentifier;

@end
