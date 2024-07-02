/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBBinaryDescriptor;
@class FBCodesignProvider;

@protocol FBControlCoreLogger;

/**
 Concrete value wrapper around a Bundle on disk.
 */
@interface FBBundleDescriptor : NSObject <NSCopying>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param name the name of the bundle. See CFBundleName. Must not be nil.
 @param identifier the bundle identifier of the bundle. Must not be nil.
 @param path the path of the bundle. Must not be nil.
 @param binary the executable image contained within the bundle. May be be nil.
 @return a new FBBundleDescriptor instance.
 */
- (instancetype)initWithName:(NSString *)name identifier:(NSString *)identifier path:(NSString *)path binary:(nullable FBBinaryDescriptor *)binary;

/**
 An initializer for FBBundleDescriptor that obtains information by inflating via NSBundle.
 This requires that a CFBundleIdentifier is set in the bundle's Info.plist.

 @param path the path of the bundle to use.
 @param error an error out for any error that occurs
 @return a new FBBundleDescriptor instance if one could be constructed, nil otherwise.
 */
+ (nullable instancetype)bundleFromPath:(NSString *)path error:(NSError **)error;

/**
 An initializer for FBBundleDescriptor that obtains information by inflating via NSBundle.
 This does not require that a CFBundleIdentifier is set in the bundle's Info.plist.

 @param path the path of the bundle to use.
 @param error an error out for any error that occurs
 @return a new FBBundleDescriptor instance if one could be constructed, nil otherwise.
 */
+ (nullable instancetype)bundleWithFallbackIdentifierFromPath:(NSString *)path error:(NSError **)error;

#pragma mark Public Methods

/**
 Updates the binary within the Framework to point to the Xcode version present on the host.
 If the binary that the receiver wraps references the developer directory for Xcode, then this method will make a best-attempt to adjust any rpaths to point to the currently selected Xcode.
 This means that if a Framework was built on one machine that has a different Xcode path to another, then this method may help to ensure that the receiver's Framwork can be linked.
 Since modifying the rpaths of a Mach-O binary will cause the code signature to become invalid, this method will also re-sign the binary using the codesigner provided.

 @param codesign the codesign implementation to codesign with.
 @param logger the logger to use.
 @param queue the queue to do work on.
 @return a Future that resolves with the relocation replacements.
 */
- (FBFuture<NSDictionary<NSString *, NSString *> *> *)updatePathsForRelocationWithCodesign:(FBCodesignProvider *)codesign logger:(id<FBControlCoreLogger>)logger queue:(dispatch_queue_t)queue;

#pragma mark Properties

/**
 The name of the bundle (CFBundleName).
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The identifier of the bundle (CFBundleIdentifier).
 */
@property (nonatomic, copy, readonly) NSString *identifier;

/**
 The path of the bundle on the filesystem.
 */
@property (nonatomic, copy, readonly) NSString *path;

/**
 The executable image contained within the bundle.
 */
@property (nonatomic, copy, readonly, nullable) FBBinaryDescriptor *binary;

@end

NS_ASSUME_NONNULL_END
