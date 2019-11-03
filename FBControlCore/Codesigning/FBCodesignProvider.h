/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Protocol for providing a codesigning implementation.
 */
@protocol FBCodesignProvider <NSObject>

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

/**
 A Default implementation of a Codesign Provider.
 */
@interface FBCodesignProvider : NSObject <FBCodesignProvider>

/**
 Identity used to codesign bundle.
 */
@property (nonatomic, copy, readonly) NSString *identityName;

/**
 @param identityName identity used to codesign bundle
 @return code sign command that signs bundles with given identity
 */
+ (instancetype)codeSignCommandWithIdentityName:(NSString *)identityName;

/**
 @return code sign command that signs bundles with the ad hoc identity.
 */
+ (instancetype)codeSignCommandWithAdHocIdentity;

@end

NS_ASSUME_NONNULL_END
