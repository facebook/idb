/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;

/**
 Represents framework that FBControlCore is dependent on
 */
@interface FBWeakFramework : NSObject

/**
 Creates and returns FBWeakFramework relative to Xcode with the given relativePath, list of checked class names and list of pre-loaded frameworks.

 @param relativePath Developer Directory relative path to the framework.
 @param requiredClassNames list of class names used to determin if framework load was successful
 @return a Weak Framework with given relativePath, list of checked class names and list of pre-loaded frameworks
 */
+ (instancetype)xcodeFrameworkWithRelativePath:(NSString *)relativePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames;

/**
 Creates and returns FBWeakFramework relative to Xcode, trying each of the given relative paths in order and loading the first one that exists on disk.

 This is used for frameworks that Apple relocates between Xcode versions (for example SimulatorKit, which moved from `Contents/Developer/Library/PrivateFrameworks` to `Contents/SharedFrameworks` in Xcode 27). The first candidate that exists relative to the developer directory wins; the remaining candidates act as backward-compatible fallbacks.

 @param relativePathCandidates Developer Directory relative paths to the framework, in priority order.
 @param requiredClassNames list of class names used to determine if framework load was successful
 @return a Weak Framework that resolves the first existing candidate path at load time.
 */
+ (instancetype)xcodeFrameworkWithRelativePathCandidates:(NSArray<NSString *> *)relativePathCandidates requiredClassNames:(NSArray<NSString *> *)requiredClassNames;

/**
  Creates and returns FBWeakFramework with the provided absolute path

  @param absolutePath The Absolute Path of the Framework.
  @param requiredClassNames list of class names used to determin if framework load was successful
  @param rootPermitted YES if this Framework can be loaded from the root user, NO otherwise.
  @return a Weak Framework with given relativePath, list of checked class names and list of pre-loaded frameworks
*/
+ (instancetype)frameworkWithPath:(NSString *)absolutePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames rootPermitted:(BOOL)rootPermitted;

/**
 Loads framework by:
 - Checking if framework is already loaded by checking existance of classes from requiredClassNames list
 - If not, loads all frameworks from requiredFrameworks list
 - Loads framework bundle
 - If it fails due to missing framework, it will try to find in fallbackDirectories and load it
 - Makes sanity check for existance of classes from requiredClassNames list
 - Provide a sanity check that any preloaded Private Frameworks match the current xcode-select version

 @param logger a logger for logging framework loading activities.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)loadWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
