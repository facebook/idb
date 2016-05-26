/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBWeakFramework.h"

#import <Foundation/FoundationErrors.h>

#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"

@interface FBWeakFramework ()

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *basePath;
@property (nonatomic, copy, readonly) NSString *relativePath;
@property (nonatomic, copy, readonly) NSArray<NSString *> *fallbackDirectories;
@property (nonatomic, copy, readonly) NSArray<NSString *> *requiredClassNames;
@property (nonatomic, copy, readonly) NSArray<FBWeakFramework *> *requiredFrameworks;

@end

@implementation FBWeakFramework

+ (NSArray<NSString *> *)xcodeFallbackDirectories
{
  return @[
    [FBControlCoreGlobalConfiguration.developerDirectory stringByAppendingPathComponent:@"../Frameworks"],
    [FBControlCoreGlobalConfiguration.developerDirectory stringByAppendingPathComponent:@"../SharedFrameworks"],
    [FBControlCoreGlobalConfiguration.developerDirectory stringByAppendingPathComponent:@"../Plugins"],
  ];
}

#pragma mark Initializers

+ (instancetype)xcodeFrameworkWithRelativePath:(NSString *)relativePath
{
  return [self xcodeFrameworkWithRelativePath:relativePath requiredClassNames:@[]];
}

+ (instancetype)xcodeFrameworkWithRelativePath:(NSString *)relativePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames
{
  return [self xcodeFrameworkWithRelativePath:relativePath requiredClassNames:requiredClassNames requiredFrameworks:@[]];
}

+ (instancetype)xcodeFrameworkWithRelativePath:(NSString *)relativePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames requiredFrameworks:(NSArray<FBWeakFramework *> *)requiredFrameworks
{
  return [[FBWeakFramework alloc]
    initWithBasePath:FBControlCoreGlobalConfiguration.developerDirectory
    relativePath:relativePath
    fallbackDirectories:self.xcodeFallbackDirectories
    requiredClassNames:requiredClassNames
    requiredFrameworks:requiredFrameworks];
}

+ (instancetype)appleConfigurationFrameworkWithRelativePath:(NSString *)relativePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames
{
  return [self appleConfigurationFrameworkWithRelativePath:relativePath requiredClassNames:requiredClassNames requiredFrameworks:@[]];
}

+ (instancetype)appleConfigurationFrameworkWithRelativePath:(NSString *)relativePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames requiredFrameworks:(NSArray<FBWeakFramework *> *)requiredFrameworks
{
  return [[FBWeakFramework alloc]
    initWithBasePath:FBControlCoreGlobalConfiguration.appleConfiguratorApplicationPath
    relativePath:relativePath
    fallbackDirectories:@[]
    requiredClassNames:requiredClassNames
    requiredFrameworks:requiredFrameworks];
}

+ (instancetype)frameworkWithPath:(NSString *)absolutePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames
{
  return [[FBWeakFramework alloc]
    initWithBasePath:absolutePath
    relativePath:@""
    fallbackDirectories:@[]
    requiredClassNames:@[]
    requiredFrameworks:@[]];
}

- (instancetype)initWithBasePath:(NSString *)basePath relativePath:(NSString *)relativePath fallbackDirectories:(NSArray<NSString *> *)fallbackDirectories requiredClassNames:(NSArray<NSString *> *)requiredClassNames requiredFrameworks:(NSArray<FBWeakFramework *> *)requiredFrameworks
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _basePath = basePath;
  _relativePath = relativePath;
  _fallbackDirectories = fallbackDirectories;
  _requiredClassNames = requiredClassNames;
  _requiredFrameworks = requiredFrameworks;
  _name = [basePath stringByAppendingPathComponent:relativePath].lastPathComponent.stringByDeletingPathExtension;

  return self;
}

#pragma mark Public

- (BOOL)loadWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error;
{
  return [self loadFromRelativeDirectory:self.basePath fallbackDirectories:self.fallbackDirectories logger:logger error:error];
}

#pragma mark Private

+ (NSString *)missingFrameworkNameWithRPathError:(NSError *)error
{
  NSString *description = error.userInfo[@"NSDebugDescription"];
  if (!description) {
    return nil;
  }

  NSRange rpathRange = [description rangeOfString:@"@rpath/"];
  if (rpathRange.location == NSNotFound) {
    return nil;
  }
  NSRange frameworkRange = [description rangeOfString:@".framework" options:NSCaseInsensitiveSearch range:NSMakeRange(rpathRange.location, description.length - rpathRange.location)];
  if (frameworkRange.location == NSNotFound) {
    frameworkRange = [description rangeOfString:@".ideplugin" options:NSCaseInsensitiveSearch range:NSMakeRange(rpathRange.location, description.length - rpathRange.location)];
    if (frameworkRange.location == NSNotFound) {
      return nil;
    }
  }
  return [description substringWithRange:NSMakeRange(rpathRange.location + rpathRange.length, frameworkRange.location - rpathRange.location - rpathRange.length + frameworkRange.length)];
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

- (BOOL)loadFromRelativeDirectory:(NSString *)relativeDirectory fallbackDirectories:(NSArray<NSString *> *)fallbackDirectories logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Checking if classes are already loaded. Error here is irrelevant (returning NO means something is not loaded)
  if ([self allRequiredClassesExistsWithError:nil] && self.requiredClassNames.count > 0) {
    // The Class exists, therefore has been loaded
    [logger logFormat:@"%@: Already loaded, skipping", self.name];
    NSError *innerError = nil;
    if (![self verifyIfLoadedWithLogger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
    return YES;
  }

  // Load required frameworks
  for (FBWeakFramework *requredFramework in self.requiredFrameworks) {
    NSError *innerError = nil;
    if(![requredFramework loadWithLogger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
  }

  // Load frameworks
  NSString *path = [[relativeDirectory stringByAppendingPathComponent:self.relativePath] stringByStandardizingPath];
  NSBundle *bundle = [NSBundle bundleWithPath:path];
  if (!bundle) {
    return [[FBControlCoreError
      describeFormat:@"Failed to load the bundle for path %@", path]
      failBool:error];
  }
  NSError *innerError;
  if (![self loadBundle:bundle fallbackDirectories:fallbackDirectories logger:logger error:&innerError]) {
    return [FBControlCoreError failBoolWithError:innerError errorOut:error];
  }
  [logger logFormat:@"%@: Successfully loaded", self.name];
  if (![self allRequiredClassesExistsWithError:&innerError]) {
    [logger logFormat:@"Failed to load %@", path.lastPathComponent];
    return [FBControlCoreError failBoolWithError:innerError errorOut:error];
  }
  if (![self verifyIfLoadedWithLogger:logger error:&innerError]) {
    return [FBControlCoreError failBoolWithError:innerError errorOut:error];
  }
  return YES;
}

- (BOOL)loadBundle:(NSBundle *)bundle fallbackDirectories:(NSArray<NSString *> *)fallbackDirectories logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSError *innerError;
  if ([bundle loadAndReturnError:&innerError]) {
    return YES;
  }

  BOOL isLinkingIssue = ([innerError.domain isEqualToString:NSCocoaErrorDomain] && innerError.code == NSExecutableLoadError);
  if (!isLinkingIssue) {
    return [FBControlCoreError failBoolWithError:innerError errorOut:error];
  }

  // If it is linking issue, try to determin missing framework
  NSString *frameworkName = [self.class missingFrameworkNameWithRPathError:innerError];
  if (!frameworkName) {
    return NO;
  }

  // Try to load missing framework with locations from
  FBWeakFramework *framework = [FBWeakFramework xcodeFrameworkWithRelativePath:frameworkName];
  for (NSString *directory in fallbackDirectories) {
    if ([framework loadFromRelativeDirectory:directory fallbackDirectories:fallbackDirectories logger:logger error:&innerError]) {
      // If successfully loaded missing library, re-try
      return [self loadBundle:bundle fallbackDirectories:fallbackDirectories logger:logger error:error];
    }
  }

  // Uncategorizable Error, return the original error
  return [[[FBControlCoreError
    describeFormat:@"An error occured loading the framework for bundle %@", bundle.bundlePath]
    causedBy:innerError]
    failBool:error];
}

/**
 Given that it is possible for FBControlCore.framework to be loaded after any of the
 Private Frameworks upon which it depends, it's possible that these Frameworks may have
 been loaded from a different Developer Directory.

 In order to prevent crazy behaviour from arising, FBControlCore will check the
 directories of these Frameworks match the one that is currently set.
 */
- (BOOL)verifyIfLoadedWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  for (NSString *requiredClassName in self.requiredClassNames) {
    if (![self verifyRelativeDirectoryForPrivateClass:requiredClassName logger:logger error:error]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)verifyRelativeDirectoryForPrivateClass:(NSString *)className logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSBundle *bundle = [NSBundle bundleForClass:NSClassFromString(className)];
  if (!bundle) {
    return [[FBControlCoreError
      describeFormat:@"Could not obtain Framework bundle for class named %@", className]
      failBool:error];
  }

  // Developer Directory is: /Applications/Xcode.app/Contents/Developer
  // The common base path is: is: /Applications/Xcode.app
  NSString *basePath = [[self.basePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
  if (![bundle.bundlePath hasPrefix:basePath]) {
    return [[FBControlCoreError
      describeFormat:@"Expected Framework %@ to be loaded for Developer Directory at path %@, but was loaded from %@", bundle.bundlePath.lastPathComponent, bundle.bundlePath, self.basePath]
      failBool:error];
  }
  [logger logFormat:@"%@: %@ has correct path of %@", self.name, className, basePath];
  return YES;
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"Name %@ | Base Path %@ | Relative Path %@ | Required Classes %@ | Required Frameworks [%@]",
    self.name,
    self.basePath,
    self.relativePath,
    self.requiredClassNames,
    self.requiredFrameworks
  ];
}

@end
