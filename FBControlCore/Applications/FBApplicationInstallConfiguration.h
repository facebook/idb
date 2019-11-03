/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for an Install
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeInstall;

/**
 A Configuration for installing Applications.
 */
@interface FBApplicationInstallConfiguration : NSObject <NSCopying, FBiOSTargetFuture>

/**
 The Designated Initializer.

 @param applicationPath the Application Path on the host.
 @param codesign YES if the install should be codesigned, NO otherwise.
 */
+ (instancetype)applicationInstallWithPath:(NSString *)applicationPath codesign:(BOOL)codesign;

/**
 The Path of the Application.
 */
@property (nonatomic, copy, readonly) NSString *applicationPath;

/**
 YES if the Application should be codesigned, NO otherwise.
 */
@property (nonatomic, assign, readonly) BOOL codesign;

@end

NS_ASSUME_NONNULL_END
