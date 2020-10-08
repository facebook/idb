/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBSpringboardServicesClient.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;

/**
 The Service Name for Managed Config.
 */
extern NSString *const FBManagedConfigService;

/**
 A client for Manged Config.
 */
@interface FBManagedConfigClient : NSObject

#pragma mark Initializers

/**
 Constructs a transport for the specified service connection.

 @param connection the connection to use.
 @param logger the logger to use.
 @return a Future that resolves with the instruments client.
 */
+ (instancetype)managedConfigClientWithConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Gets the cloud configuration for the service.

 @return a Future that resolves with the cloud configuration.
*/
- (FBFuture<NSDictionary<NSString *, id> *> *)getCloudConfiguration;

/**
 Changes the Wallpaper.

 @param name the wallpaper name enum.
 @param data the PNG data of the wallpaper.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)changeWallpaperWithName:(FBWallpaperName)name data:(NSData *)data;

/**
 Returns all of the installed MDM profiles.

 @return a Future with the profile listing.
 */
- (FBFuture<NSArray<NSString *> *> *)getProfileList;

/**
 Installs an MDM profile.

 @param payload data for the MDM Profile.
 @return a Future with the profile listing.
 */
- (FBFuture<NSNull *> *)installProfile:(NSData *)payload;

/**
 Removes a MDM profile.

 @param profileName the name of the profile
 @return a Future with the profile listing.
 */
- (FBFuture<NSNull *> *)removeProfile:(NSString *)profileName;

@end

NS_ASSUME_NONNULL_END
