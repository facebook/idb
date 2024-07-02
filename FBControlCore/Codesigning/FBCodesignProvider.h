/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Default implementation of a Codesign Provider.
 */
@interface FBCodesignProvider : NSObject

#pragma mark Initializers

/**
 Create a codesigner with an identity.

 @param identityName identity used to codesign bundle
 @param logger the logger to use for logging
 @return code sign command that signs bundles with given identity
 */
+ (instancetype)codeSignCommandWithIdentityName:(NSString *)identityName logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Create a codesigner with the ad-hoc identity

 @param logger the logger to use for logging
 @return code sign command that signs bundles with the ad hoc identity.
 */
+ (instancetype)codeSignCommandWithAdHocIdentityWithLogger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Properties

/**
 Identity used to codesign bundle.
 */
@property (nonatomic, copy, readonly) NSString *identityName;

#pragma mark Public Methods

/**
 Requests that the receiver codesigns a bundle. This only signs the main bundle, not any bundles nested within.

 @param bundlePath path to bundle that should be signed.
 @return A future that resolves when the bundle has been signed.
 */
- (FBFuture<NSNull *> *)signBundleAtPath:(NSString *)bundlePath;

/**
 Requests that the receiver codesigns a bundle and all bundles within its Frameworks directory.

 @param bundlePath path to bundle that should be signed.
 @return A future that resolves when the bundle has been signed.
 */
- (FBFuture<NSNull *> *)recursivelySignBundleAtPath:(NSString *)bundlePath;

/**
 Attempts to fetch the CDHash of a bundle.

 @param bundlePath the file path to the bundle.
 @return A future that resolves with the CDHash.
 */
- (FBFuture<NSString *> *)cdHashForBundleAtPath:(NSString *)bundlePath;

@end

NS_ASSUME_NONNULL_END
