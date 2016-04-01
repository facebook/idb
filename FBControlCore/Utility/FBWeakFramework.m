/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBWeakFramework.h"

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"

@interface FBWeakFramework ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic, copy) NSArray<NSString *> *requiredClassNames;
@property (nonatomic, copy) NSArray<FBWeakFramework *> *requiredFrameworks;
@end

@implementation FBWeakFramework

+ (instancetype)frameworkWithRelativePath:(NSString *)relativePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames
{
  return [self frameworkWithRelativePath:relativePath requiredClassNames:requiredClassNames requiredFrameworks:@[]];
}

+ (instancetype)frameworkWithRelativePath:(NSString *)relativePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames requiredFrameworks:(NSArray<FBWeakFramework *> *)requiredFrameworks
{
  NSAssert(requiredClassNames.count > 0, @"At least one class name is required to properly load and validate framework");
  FBWeakFramework *framework = [FBWeakFramework new];
  framework.relativePath = relativePath;
  framework.requiredClassNames = requiredClassNames;
  framework.requiredFrameworks = requiredFrameworks;
  framework.name = relativePath.lastPathComponent.stringByDeletingPathExtension;
  return framework;
}

- (BOOL)allRequiredClassesExistsWithError:(NSError **)error
{
  for (NSString *requiredClassName in self.requiredClassNames) {
    if (!NSClassFromString(requiredClassName)) {
      return [[FBControlCoreError
               describeFormat:@"Missing %@ class from %@ framework", requiredClassName, self.name]
              failBool:error];
    }
  }
  return YES;
}

- (BOOL)loadFromRelativeDirectory:(NSString *)developerDirectory logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Checking if classes are already loaded. Error here is irrelevant (returning NO means something is not loaded)
  if ([self allRequiredClassesExistsWithError:nil]) {
    // The Class exists, therefore has been loaded
    [logger logFormat:@"%@: Already loaded, skipping", self.name];
    NSError *innerError = nil;
    if (![self verifyIfLoadedFromRelativeDirectory:developerDirectory logger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
    return YES;
  }

  // Load required frameworks
  for (FBWeakFramework *requredFramework in self.requiredFrameworks) {
    NSError *innerError = nil;
    if(![requredFramework loadFromRelativeDirectory:developerDirectory logger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
  }

  // Load frameworks
  NSString *path = [[developerDirectory stringByAppendingPathComponent:self.relativePath] stringByStandardizingPath];
  NSBundle *bundle = [NSBundle bundleWithPath:path];
  if (!bundle) {
    return [[FBControlCoreError
             describeFormat:@"Failed to load the bundle for path %@", path]
            failBool:error];
  }
  if (![bundle loadAndReturnError:error]) {
    return [[FBControlCoreError
             describeFormat:@"Failed to load the the Framework Bundle %@", bundle]
            failBool:error];
  }
  [logger logFormat:@"%@: Successfully loaded", self.name];
  NSError *innerError;
  if (![self allRequiredClassesExistsWithError:&innerError]) {
    [logger logFormat:@"Failed to load %@", path.lastPathComponent];
    return [FBControlCoreError failBoolWithError:innerError errorOut:error];
  }
  if (![self verifyIfLoadedFromRelativeDirectory:developerDirectory logger:logger error:&innerError]) {
    return [FBControlCoreError failBoolWithError:innerError errorOut:error];
  }
  return YES;
}

/**
 Given that it is possible for FBControlCore.framework to be loaded after any of the
 Private Frameworks upon which it depends, it's possible that these Frameworks may have
 been loaded from a different Developer Directory.

 In order to prevent crazy behaviour from arising, FBControlCore will check the
 directories of these Frameworks match the one that is currently set.
 */
- (BOOL)verifyIfLoadedFromRelativeDirectory:(NSString *)developerDirectory logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  for (NSString *requiredClassName in self.requiredClassNames) {
    if (![self verifyRelativeDirectoryForPrivateClass:requiredClassName developerDirectory:developerDirectory logger:logger error:error]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)verifyRelativeDirectoryForPrivateClass:(NSString *)className developerDirectory:(NSString *)developerDirectory logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
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
  [logger logFormat:@"%@: %@ has correct path of %@", self.name, className, basePath];
  return YES;
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"Name %@ | relativePath %@ | required classes %@ | required frameworks [%@]",
    self.name,
    self.relativePath,
    self.requiredClassNames,
    self.requiredFrameworks
  ];
}

@end
