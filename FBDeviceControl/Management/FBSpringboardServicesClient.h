/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;

/**
 The wire format for the SpringBoard icon layout, as returned by the `getIconState` command
 on the `com.apple.springboardservices` lockdown service (format version 2).

 The top-level structure is an array of pages, where page 0 is the dock and pages 1..N
 are the home screen pages. Each page is an array of icon entries (dictionaries).

 There are several types of icon entry, distinguished by the keys present:

 1. Regular App Icons
    Required keys:
      - `bundleIdentifier` (NSString): The app's bundle identifier (e.g. "com.apple.mobilesafari")
      - `displayIdentifier` (NSString): Usually the same as bundleIdentifier
      - `displayName` (NSString): The user-visible app name
    Optional keys:
      - `bundleVersion` (NSString/NSNumber): The app's CFBundleVersion
      - `iconModDate` (NSString): ISO 8601 date when the icon was last modified

 2. Folders
    Required keys:
      - `listType` (NSString): Always "folder"
      - `displayName` (NSString): The folder's name (e.g. "Utilities")
      - `iconLists` (NSArray<NSArray<NSDictionary>>): Nested pages of icon entries within the folder.
        Each inner array is a page within the folder, containing regular app icon dictionaries.

 3. Siri Suggestions / App Predictions Widget
    Required keys:
      - `elementType` (NSString): "appPredictions"
      - `iconType` (NSString): "custom"
      - `displayIdentifier` (NSString): A UUID identifying this widget instance
      - `gridSize` (NSString): The widget size (e.g. "medium")
    Optional keys:
      - `allowsSuggestions` (NSNumber<BOOL>)
      - `allowsExternalSuggestions` (NSNumber<BOOL>)
      - `iconLists` (NSArray): Typically empty

 4. Offloaded / App Library Apps
    These are apps that are not currently installed but retain a position in the layout.
    Required keys:
      - `displayIdentifier` (NSString): The app's bundle identifier
      - `displayName` (NSString): The app's name
    Notable absence:
      - No `bundleIdentifier` key (this distinguishes them from installed apps)

 When setting the icon layout via `setIconState`, the same format is expected.
 Entries should be round-tripped: preserve all original keys when moving icons between positions.
 */
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
 Gets the raw Icon State response from SpringBoard for a given format version.
 Returns the raw plist object without type checking, for protocol exploration.

 @param formatVersion the format version number (e.g. 2, 3).
 @return a Future wrapping the raw response object.
 */
- (FBFuture<id> *)getRawIconState:(NSUInteger)formatVersion;

/**
 Sets the Icon Layout of Springboard.

 @param iconLayout the icon layout to set.
 @return a Future that resolves when the icon layout has been set.
 */
- (FBFuture<NSNull *> *)setIconLayout:(IconLayoutType)iconLayout;

/**
 Queries the home screen grid dimensions from SpringBoard.
 Returns a dictionary with keys like "iconColumns", "iconRows", "dockColumns", etc.

 @return a Future with the metrics dictionary.
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)getHomeScreenIconMetrics;

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
