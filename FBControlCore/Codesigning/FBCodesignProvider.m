/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCodesignProvider.h"

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreError.h"
#import "FBLogSearch.h"

static NSString *const CDHashPrefix = @"CDHash=";

@interface FBCodesignProvider ()

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBCodesignProvider

+ (instancetype)codeSignCommandWithIdentityName:(NSString *)identityName logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithIdentityName:identityName logger:logger];
}

+ (instancetype)codeSignCommandWithAdHocIdentityWithLogger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithIdentityName:@"-" logger:logger];
}

- (instancetype)initWithIdentityName:(NSString *)identityName logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _identityName = identityName;
  _logger = logger;
  _queue = dispatch_queue_create("com.facebook.fbcontrolcore.codesign", DISPATCH_QUEUE_CONCURRENT);

  return self;
}

#pragma mark - FBCodesignProvider protocol

+ (FBLogSearchPredicate *)logSearchPredicateForCDHash
{
  return [FBLogSearchPredicate substrings:@[CDHashPrefix]];
}

- (FBFuture<NSNull *> *)signBundleAtPath:(NSString *)bundlePath
{
  [self.logger logFormat:@"Signing bundle %@ with identity %@", bundlePath, self.identityName];
  return [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/codesign" arguments:@[@"-s", self.identityName, @"-f", bundlePath]]
    runUntilCompletion]
    mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)recursivelySignBundleAtPath:(NSString *)bundlePath
{
  NSMutableArray<NSString *> *pathsToSign = [NSMutableArray arrayWithObject:bundlePath];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *frameworksPath = [bundlePath stringByAppendingString:@"/Frameworks/"];
  if ([fileManager fileExistsAtPath:frameworksPath]) {
    NSError *fileSystemError;
    for (NSString *frameworkPath in [fileManager contentsOfDirectoryAtPath:frameworksPath error:&fileSystemError]) {
      [pathsToSign addObject:[frameworksPath stringByAppendingString:frameworkPath]];
    }
    if (fileSystemError) {
      return [FBControlCoreError failFutureWithError:fileSystemError];
    }
  }
  NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];
  for (NSString *pathToSign in pathsToSign) {
    [futures addObject:[self signBundleAtPath:pathToSign]];
  }
  return [[FBFuture futureWithFutures:futures] mapReplace:NSNull.null];
}

- (FBFuture<NSString *> *)cdHashForBundleAtPath:(NSString *)bundlePath
{
  id<FBControlCoreLogger> logger = self.logger;
  [logger logFormat:@"Obtaining CDHash for bundle at path %@", bundlePath];
  return [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/codesign" arguments:@[@"-dvvvv", bundlePath]]
    runUntilCompletion]
    onQueue:self.queue fmap:^(FBTask *task) {
      NSString *output = task.stdErr;
      NSString *cdHash = [[[FBLogSearch
        withText:output predicate:FBCodesignProvider.logSearchPredicateForCDHash]
        firstMatchingLine]
        stringByReplacingOccurrencesOfString:CDHashPrefix withString:@""];
      if (!cdHash) {
        return [[FBControlCoreError
          describeFormat:@"Could not find '%@' in output: %@", CDHashPrefix, output]
          failFuture];
      }
      [logger logFormat:@"Obtained CDHash %@", cdHash];
      return [FBFuture futureWithResult:cdHash];
    }];
}

@end
