/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;

typedef NSArray<NSArray<NSDictionary<NSString *, id> *> *> * IconLayoutType;

/**
 The Service Name for Managed Config.
 */
extern NSString *const FBSpringboardServiceName;

/**
 A String Enum for wallpaper names.
 */
typedef NSString *FBWallpaperName NS_STRING_ENUM;
extern FBWallpaperName const FBWallpaperNameHomescreen;
extern FBWallpaperName const FBWallpaperNameLockscreen;


/**
 A client for SpringBoardServices.
 */
@interface FBSpringboardServicesClient : NSObject

#pragma mark Initializers

/**
 Constructs a transport for the specified service connection.

 @param connection the connection to use.
 @param logger the logger to use.
 @return a Future that resolves with the instruments client.
 */
+ (instancetype)springboardServicesClientWithConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Gets the Icon Layout of Springboard.

 @return a Future wrapping the Icon Layout.
 */
- (FBFuture<IconLayoutType> *)getIconLayout;

/**
 Sets the Icon Layout of Springboard.

 @param iconLayout the icon layout to set.
 @return a Future that resolves when the icon layout has been set.
 */
- (FBFuture<NSNull *> *)setIconLayout:(IconLayoutType)iconLayout;

/**
 Obtains Wallpaper for the Homescreen.

 @param name the name of wallpaper to retrieve.
 @return a Future with the Image PNG Data.
 */
- (FBFuture<NSData *> *)wallpaperImageDataForKind:(FBWallpaperName)name;

/**
 A File Container for Icon Manipulation

 @return an FBFileContainer implementation.
 */
- (id<FBFileContainer>)iconContainer;

@end

NS_ASSUME_NONNULL_END
