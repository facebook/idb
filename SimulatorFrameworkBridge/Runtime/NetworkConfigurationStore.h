/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBNetworkConfigurationRead : NSObject
@property (nullable, nonatomic, readonly) NSDictionary<NSString *, id> *configuration;
@end

@interface FBNetworkConfigurationStore : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
+ (nullable instancetype)dnsStore;
+ (nullable instancetype)proxyStore;
/** Nil means the read API is unavailable; a result with nil configuration means the key is absent. */
- (nullable FBNetworkConfigurationRead *)readConfiguration;
- (BOOL)prepareToWrite;
- (BOOL)writeConfiguration:(NSDictionary<NSString *, id> *)configuration;
- (void)notifyChange;
@end

NS_ASSUME_NONNULL_END
