/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeltaUpdateManager+XCTest.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBDeviceControl/FBDeviceControl.h>

#import "FBIDBStorageManager.h"
#import "FBIDBError.h"
#import "FBStorageUtils.h"
#import "FBTemporaryDirectory.h"
#import "FBXCTestDescriptor.h"

static const NSTimeInterval DEFAULT_CLIENT_TIMEOUT = 60;

@interface FBXCTestDelta ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;

@end

@implementation FBXCTestDelta

- (instancetype)initWithIdentifier:(NSString *)identifier results:(NSArray<FBTestRunUpdate *> *)results logOutput:(NSString *)logOutput resultBundlePath:(NSString *)resultBundlePath state:(FBIDBTestOperationState)state error:(NSError *)error
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _identifier = identifier;
  _results = results;
  _logOutput = logOutput;
  _resultBundlePath = resultBundlePath;
  _state = state;
  _error = error;

  return self;
}

@end

@implementation FBDeltaUpdateManager (XCTest)

#pragma mark Initializers

+ (FBXCTestDeltaUpdateManager *)xctestManagerWithTarget:(id<FBiOSTarget>)target bundleStorage:(FBXCTestBundleStorage *)bundleStorage temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  return [self
    managerWithTarget:target
    name:@"xctest"
    expiration:@(DEFAULT_CLIENT_TIMEOUT)
    capacity:nil
    logger:target.logger
    create:^ FBFuture<FBIDBTestOperation *> * (FBXCTestRunRequest *request) {
      return [request startWithBundleStorageManager:bundleStorage target:target temporaryDirectory:temporaryDirectory];
    }
    delta:^(FBIDBTestOperation *operation, NSString *identifier, BOOL *done) {
      FBIDBTestOperationState state = operation.state;
      NSString *logOutput = [operation.logBuffer consumeCurrentString];
      NSString *resultBundlePath = operation.resultBundlePath;
      NSError *error = operation.completed.error;
      NSArray<FBTestRunUpdate *> *results = [operation.reporter consumeCurrentResults];
      if (state == FBIDBTestOperationStateTerminatedNormally) {
        *done = YES;
      }

      FBXCTestDelta *delta = [[FBXCTestDelta alloc]
        initWithIdentifier:identifier
        results:results
        logOutput:logOutput
        resultBundlePath:resultBundlePath
        state:state
        error:error];

      return [FBFuture futureWithResult:delta];
    }];
}

@end
