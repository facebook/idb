/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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
@property (nonatomic, copy, readonly) NSArray<NSString *> *fallbackDirectories;
@property (nonatomic, copy, readonly) NSArray<NSString *> *requiredClassNames;
@property (nonatomic, copy, readonly) NSArray<FBWeakFramework *> *requiredFrameworks;
@property (nonatomic, assign, readonly) FBWeakFrameworkType type;
@property (nonatomic, assign, readonly) BOOL rootPermitted;


@end

@implementation FBWeakFramework

+ (NSArray<NSString *> *)xcodeFallbackDirectories
{
  return @[
    [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"../Frameworks"],
    [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"../SharedFrameworks"],
    [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"../Plugins"],
  ];
}

#pragma mark Initializers

+ (instancetype)xcodeFrameworkWithRelativePath:(NSString *)relativePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames requiredFrameworks:(NSArray<FBWeakFramework *> *)requiredFrameworks rootPermitted:(BOOL)rootPermitted
{
  return [[FBWeakFramework alloc]
    initWithBasePath:FBXcodeConfiguration.developerDirectory
    relativePath:relativePath
    fallbackDirectories:self.xcodeFallbackDirectories
    requiredClassNames:requiredClassNames
    requiredFrameworks:requiredFrameworks
    rootPermitted:NO];
}

+ (instancetype)frameworkWithPath:(NSString *)absolutePath requiredClassNames:(NSArray<NSString *> *)requiredClassNames requiredFrameworks:(NSArray<FBWeakFramework *> *)requiredFrameworks rootPermitted:(BOOL)rootPermitted
{
  return [[FBWeakFramework alloc]
    initWithBasePath:absolutePath
    relativePath:@""
    fallbackDirectories:@[]
    requiredClassNames:requiredClassNames
    requiredFrameworks:requiredFrameworks
    rootPermitted:rootPermitted];
}

- (instancetype)initWithBasePath:(NSString *)basePath relativePath:(NSString *)relativePath fallbackDirectories:(NSArray<NSString *> *)fallbackDirectories requiredClassNames:(NSArray<NSString *> *)requiredClassNames requiredFrameworks:(NSArray<FBWeakFramework *> *)requiredFrameworks rootPermitted:(BOOL)rootPermitted
{
  self = [super init];
  if (!self) {
    return nil;
  }

  NSString *filename = [basePath stringByAppendingPathComponent:relativePath].lastPathComponent;

  _basePath = basePath;
  _relativePath = relativePath;
  _fallbackDirectories = fallbackDirectories;
  _requiredClassNames = requiredClassNames;
  _requiredFrameworks = requiredFrameworks;
  _name = filename.stringByDeletingPathExtension;
  _type = [filename.pathExtension isEqualToString:@"dylib"] ? FBWeakFrameworkDylib : FBWeakFrameworkTypeFramework;
  _rootPermitted = rootPermitted;

  return self;
}

#pragma mark Public

- (BOOL)loadWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error;
{
  return [self loadFromRelativeDirectory:self.basePath fallbackDirectories:self.fallbackDirectories logger:logger error:error];
}

#pragma mark Private

+ (NSString *)missingFrameworkNameWithErrorDescription:(NSString *)description
{
  if (!description) {
    return nil;
  }

  NSRange rpathRange = [description rangeOfString:@"@rpath/"];
  if (rpathRange.location == NSNotFound) {
    return nil;
  }

  NSRange searchRange = NSMakeRange(rpathRange.location, description.length - rpathRange.location);

  NSRange frameworkRange = [description rangeOfString:@".dylib"
                                              options:NSCaseInsensitiveSearch
                                                range:searchRange];

  if (frameworkRange.location == NSNotFound) {
    frameworkRange = [description rangeOfString:@".framework"
                                        options:NSCaseInsensitiveSearch
                                          range:searchRange];
  }

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
    [logger.debug logFormat:@"%@: Already loaded, skipping", self.name];
    NSError *innerError = nil;
    if (![self verifyIfLoadedWithLogger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
    return YES;
  }

  // Load required frameworks
  for (FBWeakFramework *requredFramework in self.requiredFrameworks) {
    NSError *innerError = nil;
    if (![requredFramework loadWithLogger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
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

  NSError *innerError = nil;
  switch (self.type) {
    case FBWeakFrameworkTypeFramework: {
      NSBundle *bundle = [NSBundle bundleWithPath:path];
      if (!bundle) {
        return [[FBControlCoreError
                 describeFormat:@"Failed to load the bundle for path %@", path]
                failBool:error];
      }

      [logger.debug logFormat:@"%@: Loading from %@ ", self.name, path];
      if (![self loadBundle:bundle fallbackDirectories:fallbackDirectories logger:logger error:&innerError]) {
        return [FBControlCoreError failBoolWithError:innerError errorOut:error];
      }
    }
      break;

    case FBWeakFrameworkDylib:
      if (![self loadDylibNamed:self.relativePath
              relativeDirectory:relativeDirectory
            fallbackDirectories:fallbackDirectories
                         logger:logger
                          error:error]) {
        return [[FBControlCoreError describeFormat:@"Failed to load %@", self.relativePath] failBool:error];
      }
      break;

    default:
      break;
  }

  [logger.debug logFormat:@"%@: Successfully loaded", self.name];
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
    return [[[FBControlCoreError
      describeFormat:@"Error loading bundle at %@ and it was not a linking issue", bundle.bundlePath]
      causedBy:innerError]
      failBool:error];
  }

  // If it is linking issue, try to determine missing framework
  [logger.debug logFormat:@"%@: Bundle could not be loaded from %@, attempting to find the Framework name", self.name, bundle.bundlePath];
  NSString *description = innerError.userInfo[@"NSDebugDescription"];
  NSString *missingFrameworkName = [self.class missingFrameworkNameWithErrorDescription:description];
  if (!missingFrameworkName) {
    return [[[FBControlCoreError
      describeFormat:@"Could not determine the missing framework name from %@", bundle.bundlePath]
      causedBy:innerError]
      failBool:error];
  }

  if (![self loadMissingFrameworkNamed:missingFrameworkName
                   fallbackDirectories:fallbackDirectories
                                logger:logger
                                 error:error]) {
    return [[FBControlCoreError describeFormat:@"Could not load missing framework %@", missingFrameworkName]
            failBool:error];
  }
  return [self loadBundle:bundle fallbackDirectories:fallbackDirectories logger:logger error:error];

  // Uncategorizable Error, return the original error
  return [[FBControlCoreError
    describeFormat:@"Missing Framework %@ could not be loaded from any fallback directories", missingFrameworkName]
    failBool:error];
}

- (BOOL)loadDylibNamed:(NSString *)dylibName
     relativeDirectory:(NSString *)relativeDirectory
   fallbackDirectories:(NSArray<NSString *> *)fallbackDirectories
                logger:(id<FBControlCoreLogger>)logger
                 error:(NSError **)error
{
  NSString *path = [relativeDirectory.stringByStandardizingPath stringByAppendingPathComponent:dylibName];
  if (!dlopen(path.UTF8String, RTLD_LAZY)) {
    // Error may be
    NSString *errorString = [NSString stringWithUTF8String:dlerror()];
    NSString *missingFrameworkName = [[self class] missingFrameworkNameWithErrorDescription:errorString];
    if (![self loadMissingFrameworkNamed:missingFrameworkName
                     fallbackDirectories:fallbackDirectories
                                  logger:logger
                                   error:error]) {
      return [[FBControlCoreError describeFormat:@"Failed to load dylib %@ dependency %@",
               dylibName, missingFrameworkName]
              failBool:error];
    }
    // Dependency loaded - retry
    return [self loadDylibNamed:dylibName
              relativeDirectory:relativeDirectory
            fallbackDirectories:fallbackDirectories
                         logger:logger
                   error:error];
  }
  return YES;
}

- (BOOL)loadMissingFrameworkNamed:(NSString *)missingFrameworkName fallbackDirectories:(NSArray<NSString *> *)fallbackDirectories logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Try to load missing framework with locations from
  FBWeakFramework *missingFramework = [FBWeakFramework xcodeFrameworkWithRelativePath:missingFrameworkName requiredClassNames:@[] requiredFrameworks:@[] rootPermitted:NO];
  [logger.debug logFormat:@"Attempting to load missing framework %@", missingFrameworkName];
  for (NSString *directory in fallbackDirectories) {
    NSError *missingFrameworkLoadError = nil;
    if (![missingFramework loadFromRelativeDirectory:directory fallbackDirectories:fallbackDirectories logger:logger error:&missingFrameworkLoadError]) {
      [logger.debug logFormat:@"%@ could not be loaded from fallback directory %@", missingFrameworkName, directory];
      continue;
    }
    [logger.debug logFormat:@"%@ has been loaded from fallback directory '%@', re-attempting to load %@", missingFrameworkName, directory, self.name];
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
