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
/**
 The Action Type for an Agent Launch.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeServiceInfo;

/**
 An action for fetching accessibility.
 */
@interface FBServiceInfoConfiguration : NSObject <FBiOSTargetFuture, NSCopying>

/**
 The Designated Initializer

 @param serviceName the service name
 @return a FBServiceInfoConfiguration object.
 */
+ (instancetype)configurationWithServiceName:(NSString *)serviceName;

/**
 The Service Name to Fetch.
 */
@property (nonatomic, copy, readonly) NSString *serviceName;

@end

NS_ASSUME_NONNULL_END
