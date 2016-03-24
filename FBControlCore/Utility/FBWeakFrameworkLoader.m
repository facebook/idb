/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBWeakFrameworkLoader.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"

@implementation FBWeakFrameworkLoader

// A Mapping of Class Names to the Frameworks that they belong to. This serves to:
// 1) Represent the Frameworks that FBControlCore is dependent on via their classes
// 2) Provide a path to the relevant Framework.
// 3) Provide a class for sanity checking the Framework load.
// 4) Provide a class that can be checked before the Framework load to avoid re-loading the same
//    Framework if others have done so before.
// 5) Provide a sanity check that any preloaded Private Frameworks match the current xcode-select version
+ (BOOL)loadPrivateFrameworks:(NSDictionary<NSString *, NSString *> *)classMapping logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  static BOOL hasLoaded = NO;
  if (hasLoaded) {
    return YES;
  }

  // This will assert if the directory could not be found.
  NSString *developerDirectory = FBControlCoreGlobalConfiguration.developerDirectory;
  [logger logFormat:@"Using Developer Directory %@", developerDirectory];

  for (NSString *className in classMapping) {
    NSString *relativePath = classMapping[className];
    NSString *path = [[developerDirectory stringByAppendingPathComponent:relativePath] stringByStandardizingPath];

    // The Class exists, therefore has been loaded
    if (NSClassFromString(className)) {
      [logger logFormat:@"%@ is already loaded, skipping load of framework %@", className, path];
      NSError *innerError = nil;
      if (![self verifyDeveloperDirectoryForPrivateClass:className developerDirectory:developerDirectory logger:logger error:&innerError]) {
        return [FBControlCoreError failBoolWithError:innerError errorOut:error];
      }
      continue;
    }

    // Otherwise load the Framework.
    [logger logFormat:@"%@ is not loaded. Loading %@ at path %@", className, path.lastPathComponent, path];
    NSError *innerError = nil;
    if (![self loadFrameworkAtPath:path logger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
    [logger logFormat:@"Loaded %@ from %@", className, path];
  }

  // We're done with loading Frameworks.
  hasLoaded = YES;
  [logger logFormat:@"Loaded All Private Frameworks %@", [FBCollectionInformation oneLineDescriptionFromArray:classMapping.allValues atKeyPath:@"lastPathComponent"]];

  return YES;
}

+ (BOOL)loadFrameworkAtPath:(NSString *)path logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSBundle *bundle = [NSBundle bundleWithPath:path];
  if (!bundle) {
    return [[FBControlCoreError
      describeFormat:@"Failed to load the bundle for path %@", path]
      failBool:error];
  }

  NSError *innerError = nil;
  if (![bundle loadAndReturnError:&innerError]) {
    return [[FBControlCoreError
      describeFormat:@"Failed to load the the Framework Bundle %@", bundle]
      failBool:error];
  }
  [logger logFormat:@"Successfully loaded %@", path.lastPathComponent];
  return YES;
}

/**
 Given that it is possible for FBControlCore.framework to be loaded after any of the
 Private Frameworks upon which it depends, it's possible that these Frameworks may have
 been loaded from a different Developer Directory.

 In order to prevent crazy behaviour from arising, FBControlCore will check the
 directories of these Frameworks match the one that is currently set.
 */
+ (BOOL)verifyDeveloperDirectoryForPrivateClass:(NSString *)className developerDirectory:(NSString *)developerDirectory logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSBundle *bundle = [NSBundle bundleForClass:NSClassFromString(className)];
  if (!bundle) {
    return [[FBControlCoreError
      describeFormat:@"Could not obtain Framework bundle for class named %@", className]
      failBool:error];
  }

  // Developer Directory is: /Applications/Xcode.app/Contents/Developer
  // The common base path is: is: /Applications/Xcode.app
  NSString *basePath = [[developerDirectory stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
  if (![bundle.bundlePath hasPrefix:basePath]) {
    return [[FBControlCoreError
      describeFormat:@"Expected Framework %@ to be loaded for Developer Directory at path %@, but was loaded from %@", bundle.bundlePath.lastPathComponent, bundle.bundlePath, developerDirectory]
      failBool:error];
  }
  [logger logFormat:@"%@ has correct path of %@", className, basePath];
  return YES;
}

@end
