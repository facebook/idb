/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBDeviceCommands;
@protocol FBControlCoreLogger;

@interface FBDeveloperDiskImage : NSObject

#pragma mark Initializers

/**
 Finds the Disk Image for the given device, if one can be found.
 If an exact match is not found, the closest match will be used.

 @param targetVersion the device to target.
 @param logger the logger to log to.
 @param error an error out for any error that occurs.
 @return the path of the disk image.
 */
+ (nullable instancetype)developerDiskImage:(NSOperatingSystemVersion)targetVersion logger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error;

/**
 Returns all of the Developer Disk Images that are available.
 These Disk Images are found by inspecting the appropriate directories within the current installed Xcode.
 */
+ (NSArray<FBDeveloperDiskImage *> *)allDiskImages;

#pragma mark Properties

/**
 The path of the disk image.
 */
@property (nonatomic, copy, readonly) NSString *diskImagePath;

/**
 The path of the signature.
 */
@property (nonatomic, copy, readonly) NSData *signature;

/**
 The OS Version that the Disk Image is intended for.
 */
@property (nonatomic, assign, readonly) NSOperatingSystemVersion version;

/**
 The Xcode version associated with the disk image.
 */
@property (nonatomic, assign, readonly) NSOperatingSystemVersion xcodeVersion;

#pragma mark Public

/**
 Returns the path for the symbols of the device.

 @param buildVersion the device build version to target.
 @param logger the logger to log to.
 @param error an error out for any error that occurs.
 */
+ (NSString *)pathForDeveloperSymbols:(NSString *)buildVersion logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

/**
 Returns the best match for the provided image list.

 @param images the images to search.
 @param targetVersion the version to target.
 @param logger the logger to log to.
 @param error an error out for any error that occurs.
 @return a disk image, or nil if no suitable image could be found.
 */
+ (nullable FBDeveloperDiskImage *)bestImageForImages:(NSArray<FBDeveloperDiskImage *> *)images targetVersion:(NSOperatingSystemVersion)targetVersion logger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
