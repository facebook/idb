/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBDebugDescribeable.h>

NS_ASSUME_NONNULL_BEGIN

@class FBBinaryDescriptor;
@protocol FBFileManager;

/**
 Concrete value wrapper around a Bundle on disk.
 Unlike NSBundle, FBBundleDescriptor is serializable. It represents the meta-information about a bundle, not the reified bundle instance itself.
 */
@interface FBBundleDescriptor : NSObject <NSCopying, FBJSONSerializable, FBDebugDescribeable>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param name the Name of the Application. See CFBundleName. Must not be nil.
 @param path The Path to the Application Bundle. Must not be nil.
 @param bundleID the Bundle ID of the Application. Must not be nil.
 @param binary the Path to the binary inside the Application. Must not be nil.
 @return a new FBBundleDescriptor instance.
 */
- (instancetype)initWithName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(nullable FBBinaryDescriptor *)binary;

/**
 An initializer for FBBundleDescriptor that obtains information by inspecting the Info.plist.

 @param path the path of the bundle to use.
 @param error an error out for any error that occurs
 @return a new FBBundleDescriptor instance if one could be constructed, nil otherwise.
 */
+ (nullable instancetype)bundleFromPath:(NSString *)path error:(NSError **)error;

#pragma mark Public Methods

/**
 Relocates the reciever into a destination directory.

 @param destinationDirectory the Destination Path to relocate to. Must not be nil.
 @param fileManager the fileManager to use. Must not be nil.
 @param error an error out for any error that occurs.
 */
- (nullable instancetype)relocateBundleIntoDirectory:(NSString *)destinationDirectory fileManager:(id<FBFileManager>)fileManager error:(NSError **)error;


#pragma mark Properties

/**
 The name of the Application. See CFBundleName.
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The File Path to the Application.
 */
@property (nonatomic, copy, readonly) NSString *path;

/**
 The Bundle Identifier of the Application. See CFBundleIdentifier.
 */
@property (nonatomic, copy, readonly) NSString *bundleID;

/**
 The Executable Binary contained within the Application's Bundle.
 */
@property (nonatomic, copy, readonly, nullable) FBBinaryDescriptor *binary;

@end

NS_ASSUME_NONNULL_END
