/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCodesignProvider.h"

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreError.h"

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

+ (NSRegularExpression *)cdHashRegex
{
  static dispatch_once_t onceToken;
  static NSRegularExpression *regex;
  dispatch_once(&onceToken, ^{
    regex = [NSRegularExpression regularExpressionWithPattern:@"CDHash=(.+)" options:0 error:nil];
  });
  return regex;
}

- (FBFuture<NSNull *> *)signBundleAtPath:(NSString *)bundlePath
{
  NSError *error = nil;
  [self makeCodesignatureWritable:bundlePath error:&error];
  if (error) {
    return [FBFuture futureWithError:error];
  }
  id<FBControlCoreLogger> logger = self.logger;
  [logger logFormat:@"Signing bundle %@ with identity %@", bundlePath, self.identityName];
  
  return [[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/codesign" arguments:@[@"-s", self.identityName, @"-f", bundlePath]]
    withStdOutInMemoryAsString]
    withStdErrInMemoryAsString]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:nil]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (FBProcess<NSNull *, NSString *, NSString *> *task) {
      NSNumber *exitCode = task.exitCode.result;
      if (![exitCode isEqualTo:@0]) {
        return [[FBControlCoreError
          describeFormat:@"Codesigning failed with exit code %@, %@\n%@", exitCode, task.stdOut, task.stdErr]
          failFuture];
      }
      [logger logFormat:@"Successfully signed bundle %@", task.stdErr];
      return FBFuture.empty;
    }];
}

- (void)makeCodesignatureWritable:(NSString *)bundlePath error:(NSError **)error
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *codeSignatureFile = [bundlePath stringByAppendingString:@"/_CodeSignature/CodeResources"];
  if (![fileManager fileExistsAtPath:codeSignatureFile]) {
    return;
  }
  if ([fileManager isWritableFileAtPath:codeSignatureFile]) {
    return;
  }
  NSMutableDictionary<NSFileAttributeKey, id> *attributes = [NSMutableDictionary dictionaryWithDictionary:[fileManager attributesOfItemAtPath:codeSignatureFile error:error]];
  if (*error) {
    [self.logger logFormat:@"Failed to get attributes of code sign file: %@", *error];
    return;
  }
  // Add user writable
  short newPermissions = [(NSNumber *)attributes[NSFilePosixPermissions] shortValue] | 0b010000000;
  attributes[NSFilePosixPermissions] = [NSNumber numberWithShort:newPermissions];
  [fileManager setAttributes:[NSDictionary dictionaryWithDictionary:attributes] ofItemAtPath:codeSignatureFile error:error];
  if (*error) {
    [self.logger logFormat:@"Failed to set attributes of code sign file: %@", *error];
  }
  [self.logger log:@"Added user writable permission to code sign file"];
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
  return [[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/codesign" arguments:@[@"-dvvvv", bundlePath]]
    withStdOutInMemoryAsString]
    withStdErrInMemoryAsString]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:nil]
    onQueue:self.queue fmap:^ FBFuture<NSString *> * (FBProcess<NSNull *,NSString *,NSString *> *task) {
      NSNumber *exitCode = task.exitCode.result;
      if (![exitCode isEqualTo:@0]) {
        return [[FBControlCoreError
          describeFormat:@"Checking CDHash of codesign execution failed %@, %@\n%@", exitCode, task.stdOut, task.stdErr]
          failFuture];
      }
      NSString *output = task.stdErr;
      NSTextCheckingResult *result = [FBCodesignProvider.cdHashRegex firstMatchInString:task.stdErr options:0 range:NSMakeRange(0, output.length)];
      if (!result) {
        return [[FBControlCoreError
          describeFormat:@"Could not find 'CDHash' in output: %@", output]
          failFuture];
      }
      NSString *cdHash = [output substringWithRange:[result rangeAtIndex:1]];
      [logger logFormat:@"Successfully obtained hash %@ from bundle %@", cdHash, bundlePath];
      return [FBFuture futureWithResult:cdHash];
    }];
}

@end
