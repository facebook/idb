/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBControlCoreFrameworkLoader.h"

#import "FBControlCore-Swift.h"
#import "FBControlCore-SwiftImport.h"
#import "FBControlCoreLogger.h"

@implementation FBControlCoreFrameworkLoader

#pragma mark Initializers

+ (instancetype)loaderWithName:(NSString *)frameworkName frameworks:(NSArray<FBWeakFramework *> *)frameworks
{
  return [[self alloc] initWithName:frameworkName frameworks:frameworks];
}

- (instancetype)initWithName:(NSString *)frameworkName frameworks:(NSArray<FBWeakFramework *> *)frameworks
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _frameworkName = frameworkName;
  _frameworks = frameworks;
  _hasLoadedFrameworks = NO;

  return self;
}

#pragma mark Public Methods.

- (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (self.hasLoadedFrameworks) {
    return YES;
  }
  BOOL result = [FBControlCoreFrameworkLoader loadPrivateFrameworks:self.frameworks logger:logger error:error];
  if (result) {
    _hasLoadedFrameworks = YES;
  }
  return result;
}

#pragma mark Private

+ (BOOL)loadPrivateFrameworks:(NSArray<FBWeakFramework *> *)weakFrameworks logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  for (FBWeakFramework *framework in weakFrameworks) {
    NSError *innerError = nil;
    if (![framework loadWithLogger:logger error:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
  }

  NSArray<NSString *> *frameworkNames = [weakFrameworks valueForKeyPath:@"@unionOfObjects.name"];
  if (frameworkNames) {
    [logger.debug log:
     [NSString stringWithFormat:@"Loaded All Private Frameworks %@",
      [FBCollectionInformation oneLineDescriptionFromArray:frameworkNames atKeyPath:@"lastPathComponent"]]
    ];
  }

  return YES;
}

@end
