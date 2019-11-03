/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBInstalledApplication;

@protocol FBCodesignProvider;
@protocol FBFileManager;

/**
 Represents product bundle (eg. .app, .xctest, .framework)
 */
@interface FBProductBundle : NSObject

/**
 The name of the bundle
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The name of the bundle with extension
 */
@property (nonatomic, copy, readonly) NSString *filename;

/**
 Full path to bundle
 */
@property (nonatomic, copy, readonly) NSString *path;

/**
 Bundle ID of the bundle
 */
@property (nonatomic, copy, readonly) NSString *bundleID;

/**
 Binary name
 */
@property (nonatomic, copy, readonly) NSString *binaryName;

/**
 Full path to binary
 */
@property (nonatomic, copy, readonly) NSString *binaryPath;

@end

/**
 Prepares FBProductBundle by:
 - coping it to workingDirectory, if set
 - codesigning bundle with codesigner, if set
 - loading bundle information from Info.plist file
 */
@interface FBProductBundleBuilder : NSObject

/**
 @return builder that uses [NSFileManager defaultManager] as file manager
 */
+ (instancetype)builder;

/**
 @param fileManager a file manager used with builder
 @return builder
 */
+ (instancetype)builderWithFileManager:(id<FBFileManager>)fileManager;

/**
 @required

 @param bundlePath path to product bundle (eg. .app, .xctest, .framework)
 @return builder
 */
- (instancetype)withBundlePath:(NSString *)bundlePath;

/**
 @optional

 @param bundleID bundle id of the application, If passed will, skip loading information from plist
 @return builder
 */
- (instancetype)withBundleID:(NSString *)bundleID;

/**
 @optional

 @param binaryName binary name of the application, If passed will, skip loading information from plist
 @return builder
 */
- (instancetype)withBinaryName:(NSString *)binaryName;

/**
 @param workingDirectory if not nil product bundle will be copied to this directory
 @return builder
 */
- (instancetype)withWorkingDirectory:(NSString *)workingDirectory;

/**
 @param codesignProvider object used to codesign product bundle
 @return builder
 */
- (instancetype)withCodesignProvider:(id<FBCodesignProvider>)codesignProvider;

/**
 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return prepared product bundle if the operation succeeds, otherwise nil.
 */
- (nullable FBProductBundle *)buildWithError:(NSError **)error;

/**
 Make a Product Bundle from an FBInstalledApplication.

 @param installedApplication the application install.
 @param error an error out for any error occurs
 @return A Product bundle, or nil on error.
 */
+ (nullable FBProductBundle *)productBundleFromInstalledApplication:(FBInstalledApplication *)installedApplication error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
