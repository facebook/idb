/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProductBundle.h"
#import "FBProductBundle+Private.h"

#import "FBCodesignProvider.h"
#import "FBFileManager.h"
#import "NSFileManager+FBFileManager.h"

@interface FBProductBundle ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *binaryName;
@property (nonatomic, copy) NSString *binaryPath;
@end

@implementation FBProductBundle

- (instancetype)copyLocatedInDirectory:(NSString *)directory
{
  FBProductBundle *bundle = [self.class new];
  bundle.bundleID = self.bundleID;
  bundle.name = self.name;
  bundle.filename = self.filename;
  bundle.path = [directory stringByAppendingPathComponent:self.filename];
  bundle.binaryName = self.binaryName;
  bundle.binaryPath = [bundle.path stringByAppendingPathComponent:self.binaryName];
  return bundle;
}

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

- (FBProductBundle *)build
{
  NSAssert(self.bundlePath, @"bundlePath is required to load product bundle");

  NSString *targetBundlePath = self.bundlePath;
  if (self.workingDirectory) {
    NSAssert(self.fileManager, @"fileManager is required to copy product bundle");
    NSError *error;
    NSString *bundleName = self.bundlePath.lastPathComponent;

    if (![self.fileManager fileExistsAtPath:self.workingDirectory]) {
      if(![self.fileManager createDirectoryAtPath:self.workingDirectory withIntermediateDirectories:YES attributes:nil error:&error]){
        return nil;
      }
    }

    targetBundlePath = [self.workingDirectory stringByAppendingPathComponent:bundleName];
    if ([self.fileManager fileExistsAtPath:targetBundlePath]) {
      [self.fileManager removeItemAtPath:targetBundlePath error:&error];
    }
    if(![self.fileManager copyItemAtPath:self.bundlePath
                                  toPath:targetBundlePath
                                   error:&error]) {
      return nil;
    }
  }

  if (self.codesignProvider && ![self.codesignProvider signBundleAtPath:targetBundlePath]) {
    return nil;
  }

  NSDictionary *infoPlist = [self.fileManager dictionaryWithPath:[self.bundlePath stringByAppendingPathComponent:@"Info.plist"]];
  if (!infoPlist) {
    infoPlist = [self.fileManager dictionaryWithPath:[self.bundlePath stringByAppendingPathComponent:@"Contents/Info.plist"]];
  }
  FBProductBundle *bundleProduct = [self.productClass new];
  bundleProduct.path = targetBundlePath;
  bundleProduct.filename = targetBundlePath.lastPathComponent;
  bundleProduct.name = targetBundlePath.lastPathComponent.stringByDeletingPathExtension;
  bundleProduct.bundleID = self.bundleID ?: infoPlist[@"CFBundleIdentifier"];
  bundleProduct.binaryName = self.binaryName ?: infoPlist[@"CFBundleExecutable"];
  bundleProduct.binaryPath = (bundleProduct.binaryName ? [targetBundlePath stringByAppendingPathComponent:bundleProduct.binaryName] : nil);
  return bundleProduct;
}

@end
