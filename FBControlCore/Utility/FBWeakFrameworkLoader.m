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
#import "FBWeakFramework.h"

@implementation FBWeakFrameworkLoader

// A Mapping of Class Names to the Frameworks that they belong to. This serves to:
// 1) Represent the Frameworks that FBControlCore is dependent on via their classes
// 2) Provide a path to the relevant Framework.
// 3) Provide a class for sanity checking the Framework load.
// 4) Provide a class that can be checked before the Framework load to avoid re-loading the same
//    Framework if others have done so before.
// 5) Provide a sanity check that any preloaded Private Frameworks match the current xcode-select version
+ (BOOL)loadPrivateFrameworks:(NSArray<FBWeakFramework *> *)weakFrameworks logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  static BOOL hasLoaded = NO;
  if (hasLoaded) {
    return YES;
  }

  // This will assert if the directory could not be found.
  NSString *developerDirectory = FBControlCoreGlobalConfiguration.developerDirectory;
  [logger logFormat:@"Using Developer Directory %@", developerDirectory];

  NSArray *fallbackDirectories =
  @[
    [developerDirectory stringByAppendingPathComponent:@"../Frameworks"],
    [developerDirectory stringByAppendingPathComponent:@"../SharedFrameworks"],
  ];

  for (FBWeakFramework *framework in weakFrameworks) {
    NSError *innerError = nil;
    if (![framework loadFromRelativeDirectory:developerDirectory fallbackDirectories:fallbackDirectories logger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
  }

  // We're done with loading Frameworks.
  hasLoaded = YES;
  [logger logFormat:@"Loaded All Private Frameworks %@", [FBCollectionInformation oneLineDescriptionFromArray:[weakFrameworks valueForKeyPath:@"@unionOfObjects.name"] atKeyPath:@"lastPathComponent"]];

  return YES;
}

@end
