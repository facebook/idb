/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Commands Related to Provisioning Profiles.
 */
@protocol FBProvisioningProfileCommands <NSObject, FBiOSTargetCommand>

/**
 Obtains all of the information about provisioning profiles

 @return A future that resolves with the Video Recording session.
 */
- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)allProvisioningProfiles;

/**
 Removes a Provisioning Profile.

 @param uuid the uuid of the profile to remove.
 @return A future that resolves the details of the removed profile
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)removeProvisioningProfile:(NSString *)uuid;

/**
 Installs a provisioning profile.

 @param profileData the data of the provisioning profile to install
 @return A future that resolves with installed provisioning profile.
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)installProvisioningProfile:(NSData *)profileData;

@end

NS_ASSUME_NONNULL_END
