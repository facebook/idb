/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFileContainerTestHelpers.h"

@interface FBFileContainerTestHelpers ()
@property (nonatomic, strong) id<FBFileContainer> wrapped;
@end

@implementation FBFileContainerTestHelpers

+ (FBFileContainerTestHelpers *)containerForBasePath:(NSString *)basePath
{
  FBFileContainerTestHelpers *helpers = [[FBFileContainerTestHelpers alloc] init];
  helpers.wrapped = [FBFileContainer fileContainerForBasePath:basePath];
  return helpers;
}

+ (FBFileContainerTestHelpers *)containerForPathMapping:(NSDictionary<NSString *, NSString *> *)pathMapping
{
  FBFileContainerTestHelpers *helpers = [[FBFileContainerTestHelpers alloc] init];
  helpers.wrapped = [FBFileContainer fileContainerForPathMapping:pathMapping];
  return helpers;
}

- (FBFuture<NSNull *> *)copyFromHost:(NSString *)sourcePath toContainer:(NSString *)destinationPath
{
  return [self.wrapped copyFromHost:sourcePath toContainer:destinationPath];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)sourcePath toHost:(NSString *)destinationPath
{
  return [self.wrapped copyFromContainer:sourcePath toHost:destinationPath];
}

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)path toConsumer:(id<FBDataConsumer>)consumer
{
  return [self.wrapped tail:path toConsumer:consumer];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [self.wrapped createDirectory:directoryPath];
}

- (FBFuture<NSNull *> *)moveFrom:(NSString *)sourcePath to:(NSString *)destinationPath
{
  return [self.wrapped moveFrom:sourcePath to:destinationPath];
}

- (FBFuture<NSNull *> *)remove:(NSString *)path
{
  return [self.wrapped remove:path];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [self.wrapped contentsOfDirectory:path];
}

@end
