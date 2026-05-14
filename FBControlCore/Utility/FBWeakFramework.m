/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBWeakFramework.h"

#import <dlfcn.h>
#import <Foundation/Foundation.h>

#import "FBControlCoreError.h"
#import "FBXcodeConfiguration.h"
#import "FBControlCoreLogger.h"

typedef NS_ENUM(NSInteger, FBWeakFrameworkType) {
  FBWeakFrameworkTypeFramework,
  FBWeakFrameworkDylib,
};

@interface FBWeakFramework ()

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *basePath;
@property (nonatomic, copy, readonly) NSString *relativePath;
@property (nonatomic, copy, readonly) NSArray<NSString *> *requiredClassNames;
@property (nonatomic, assign, readonly) BOOL rootPermitted;


@end

@implementation FBWeakFramework

#pragma mark Initializers

+ (instancetype)xcodeFrameworkWithRelativePath:(NSString *)relativePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames
{
  return [[FBWeakFramework alloc]
    initWithBasePath:FBXcodeConfiguration.developerDirectory
    relativePath:relativePath
    requiredClassNames:requiredClassNames
    rootPermitted:NO];
}

+ (instancetype)frameworkWithPath:(NSString *)absolutePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames rootPermitted:(BOOL)rootPermitted
{
  return [[FBWeakFramework alloc]
    initWithBasePath:absolutePath
    relativePath:@""
    requiredClassNames:requiredClassNames
    rootPermitted:rootPermitted];
}

- (instancetype)initWithBasePath:(NSString *)basePath relativePath:(NSString *)relativePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames rootPermitted:(BOOL)rootPermitted
{
  self = [super init];
  if (!self) {
    return nil;
  }

  NSString *filename = [basePath stringByAppendingPathComponent:relativePath].lastPathComponent;

  _basePath = basePath;
  _relativePath = relativePath;
  _requiredClassNames = requiredClassNames;
  _name = filename.stringByDeletingPathExtension;
  _rootPermitted = rootPermitted;

  return self;
}

#pragma mark Public

- (BOOL)loadWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error;
{
  return [self loadFromRelativeDirectory:self.basePath logger:logger error:error];
}

#pragma mark Private

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

- (BOOL)loadFromRelativeDirectory:(NSString *)relativeDirectory logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Checking if classes are already loaded. Error here is irrelevant (returning NO means something is not loaded)
  if ([self allRequiredClassesExistsWithError:nil] && self.requiredClassNames.count > 0) {
    // The Class exists, therefore has been loaded
    [logger.debug logFormat:@"%@: Already loaded, skipping", self.name];
    NSError *innerError = nil;
    if (![self verifyIfLoadedWithLogger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
    return YES;
  }

  // Check that the framework can be loaded as root if root.
  if ([NSUserName() isEqualToString:@"root"] && self.rootPermitted == NO) {
    return [[FBControlCoreError
      describeFormat:@"%@ cannot be loaded from the root user. Don't run this as root.", self.relativePath]
      failBool:error];
  }

  // Load frameworks
  NSString *path = [[relativeDirectory stringByAppendingPathComponent:self.relativePath] stringByStandardizingPath];
  if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:nil]) {
    return [[FBControlCoreError
      describeFormat:@"Attempting to load a file at path '%@', but it does not exist", path]
      failBool:error];
  }

  NSBundle *bundle = [NSBundle bundleWithPath:path];
  if (!bundle) {
    return [[FBControlCoreError
      describeFormat:@"Failed to load the bundle for path %@", path]
      failBool:error];
  }

  [logger.debug logFormat:@"%@: Loading from %@ ", self.name, path];
  if (![bundle loadAndReturnError:error]) {
    return NO;
  }

  [logger.debug logFormat:@"%@: Successfully loaded", self.name];
  if (![self allRequiredClassesExistsWithError:error]) {
    [logger logFormat:@"Failed to load %@", path.lastPathComponent];
    return NO;
  }
  if (![self verifyIfLoadedWithLogger:logger error:error]) {
    return NO;
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
  [logger.debug logFormat:@"%@: %@ has correct path of %@", self.name, className, basePath];
  return YES;
}

@end
