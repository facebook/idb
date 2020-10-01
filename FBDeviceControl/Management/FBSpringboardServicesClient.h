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

typedef NSArray<id> * IconLayoutType;

/**
 The Service Name for Managed Config.
 */
extern NSString *const FBSpringboardServiceName;

/**
 A client for SpringBoardServices.
 */
@interface FBSpringboardServicesClient : NSObject

#pragma mark Initializers

/**
 Constructs a transport for the specified service connection.

 @param connection the connection to use.
 @param logger the logger to use.
 @return a Future that resolves with the instruments client.
 */
+ (instancetype)springboardServicesClientWithConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Gets the Icon Layout of Springboard.

 @return a Future wrapping the Icon Layout.
 */
- (FBFuture<IconLayoutType> *)getIconLayout;

@end

NS_ASSUME_NONNULL_END
