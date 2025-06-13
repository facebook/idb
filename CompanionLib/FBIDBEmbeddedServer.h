/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBIDBCommandExecutor;
@class FBIDBStorageManager;
@class FBTemporaryDirectory;
@protocol FBiOSTarget;
@protocol FBControlCoreLogger;
@protocol FBEventReporter;

NS_ASSUME_NONNULL_BEGIN

/**
 * Embedded server for direct in-process usage of CompanionLib
 * Bypasses network communication and signal handling
 */
@interface FBIDBEmbeddedServer : NSObject

/**
 * Indicates if server is running in embedded mode
 */
@property (nonatomic, assign, readonly) BOOL embeddedMode;

/**
 * The target being controlled
 */
@property (nonatomic, strong, readonly) id<FBiOSTarget> target;

/**
 * The command executor
 */
@property (nonatomic, strong, readonly) FBIDBCommandExecutor *commandExecutor;

/**
 * Creates an embedded server instance
 *
 * @param target The iOS target (simulator or device)
 * @param logger The logger to use
 * @param error Out parameter for any errors
 * @return A new embedded server instance, or nil on error
 */
+ (nullable instancetype)embeddedServerWithTarget:(id<FBiOSTarget>)target
                                           logger:(id<FBControlCoreLogger>)logger
                                            error:(NSError **)error;

/**
 * Starts the embedded server
 *
 * @param error Out parameter for any errors
 * @return YES if successful, NO otherwise
 */
- (BOOL)startWithError:(NSError **)error;

/**
 * Shuts down the embedded server
 */
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END