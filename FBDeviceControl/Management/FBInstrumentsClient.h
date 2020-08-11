/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;

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
+ (FBFuture<FBInstrumentsClient *> *)instrumentsClientWithServiceConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Returns the list of running applications.

 @return a Dictionary, mapping process name to pid.
 */
- (FBFuture<NSDictionary<NSString *, NSNumber *> *> *)runningApplications;

@end

NS_ASSUME_NONNULL_END
