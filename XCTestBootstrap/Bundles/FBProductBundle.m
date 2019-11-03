/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProductBundle.h"
#import "FBProductBundle+Private.h"

#import <FBControlCore/FBControlCore.h>

#import "XCTestBootstrapError.h"

@interface FBProductBundle ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *binaryName;
@property (nonatomic, copy) NSString *binaryPath;
@end

@implementation FBProductBundle

@end

@implementation FBProductBundleBuilder

+ (instancetype)builder
{
  return [self.class builderWithFileManager:[NSFileManager defaultManager]];
}

+ (instancetype)builderWithFileManager:(id<FBFileManager>)fileManager
{
  FBProductBundleBuilder *builder = [self.class new];
  builder.fileManager = fileManager;
  return builder;
}

- (Class)productClass
{
  return FBProductBundle.class;
}

- (instancetype)withBundlePath:(NSString *)bundlePath
{
  self.bundlePath = bundlePath;
  return self;
}

- (instancetype)withBundleID:(NSString *)bundleID
{
  self.bundleID = bundleID;
  return self;
}

- (instancetype)withBinaryName:(NSString *)binaryName
{
  self.binaryName = binaryName;
  return self;
}

- (instancetype)withCodesignProvider:(id<FBCodesignProvider>)codesignProvider
{
  self.codesignProvider = codesignProvider;
  return self;
}

- (instancetype)withWorkingDirectory:(NSString *)workingDirectory
{
  self.workingDirectory = workingDirectory;
  return self;
}

- (FBProductBundle *)buildWithError:(NSError **)error
{
  NSAssert(self.bundlePath, @"bundlePath is required to load product bundle");
  NSString *targetBundlePath = self.bundlePath;
  if (self.workingDirectory) {
    NSAssert(self.fileManager, @"fileManager is required to copy product bundle");
    NSString *bundleName = self.bundlePath.lastPathComponent;

    if (![self.fileManager fileExistsAtPath:self.workingDirectory]) {
      if (![self.fileManager createDirectoryAtPath:self.workingDirectory withIntermediateDirectories:YES attributes:nil error:error]){
        return nil;
      }
    }

    targetBundlePath = [self.workingDirectory stringByAppendingPathComponent:bundleName];
    if ([self.fileManager fileExistsAtPath:targetBundlePath]) {
      if (![self.fileManager removeItemAtPath:targetBundlePath error:error]) {
        return nil;
      }
    }
    if (![self.fileManager copyItemAtPath:self.bundlePath
                                  toPath:targetBundlePath
                                   error:error]) {
      return nil;
    }
  }

  NSError *innerError = nil;
  if (self.codesignProvider && ![[self.codesignProvider signBundleAtPath:targetBundlePath] await:&innerError]) {
    return [[[XCTestBootstrapError
      describeFormat:@"Failed to codesign %@", targetBundlePath]
      causedBy:innerError]
      fail:error];
  }

  // Use the infoPlist if these values aren't already set.
  NSDictionary *infoPlist = [self.fileManager dictionaryWithPath:[self.bundlePath stringByAppendingPathComponent:@"Info.plist"]];
  if (!infoPlist) {
    infoPlist = [self.fileManager dictionaryWithPath:[self.bundlePath stringByAppendingPathComponent:@"Contents/Info.plist"]];
  }
  if (!infoPlist) {
    infoPlist = [self.fileManager dictionaryWithPath:[self.bundlePath stringByAppendingPathComponent:@"Resources/Info.plist"]];
  }

  FBProductBundle *bundleProduct = [self.productClass new];
  bundleProduct.binaryName = self.binaryName ?: infoPlist[@"CFBundleExecutable"];
  if (!bundleProduct.binaryName) {
    return [[XCTestBootstrapError
      describeFormat:@"No binary name provided and one could not be obtained from the Info.plist of %@", self.bundlePath]
      fail:error];
  }
  bundleProduct.bundleID = self.bundleID ?: infoPlist[@"CFBundleIdentifier"];
  if (!bundleProduct.bundleID) {
    return [[XCTestBootstrapError
      describeFormat:@"No bundle id provided and one could not be obtained from the Info.plist of %@", self.bundlePath]
      fail:error];
  }

  NSString *binaryPath = nil;
  if (bundleProduct.binaryName) {
    binaryPath = [targetBundlePath stringByAppendingPathComponent:bundleProduct.binaryName];
    if (![self.fileManager fileExistsAtPath:binaryPath]) {
      binaryPath = [[targetBundlePath stringByAppendingPathComponent:@"Contents/MacOS"] stringByAppendingPathComponent:bundleProduct.binaryName];
    }
  }
  bundleProduct.path = targetBundlePath;
  bundleProduct.filename = targetBundlePath.lastPathComponent;
  bundleProduct.name = targetBundlePath.lastPathComponent.stringByDeletingPathExtension;
  bundleProduct.binaryPath = binaryPath;
  return bundleProduct;
}

+ (FBProductBundle *)productBundleFromInstalledApplication:(FBInstalledApplication *)installedApplication error:(NSError **)error
{
  return [[[[[self builder]
    withBundlePath:installedApplication.bundle.path]
    withBundleID:installedApplication.bundle.identifier]
    withBinaryName:installedApplication.bundle.name]
    buildWithError:error];
}

@end
