/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBListApplicationsConfiguration.h"

#import "FBiOSTarget.h"
#import "FBEventReporterSubject.h"
#import "FBControlCoreError.h"
#import "FBApplicationCommands.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeListApplications = @"list_apps";

@implementation FBListApplicationsConfiguration

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeListApplications;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  id<FBApplicationCommands> commands = (id<FBApplicationCommands>) target;
  if (![target conformsToProtocol:@protocol(FBApplicationCommands)]) {
    return [[FBControlCoreError
      describeFormat:@"%@ does not support FBApplicationCommands", target]
      failFuture];
  }
  return [[commands
    installedApplications]
    onQueue:target.workQueue map:^(NSArray<id<FBJSONSerializable>> *applications) {
      id<FBEventReporterSubject> subject = [FBEventReporterSubject subjectWithName:FBEventNameListApps type:FBEventTypeDiscrete values:applications];
      [reporter report:subject];
      return FBiOSTargetContinuationDone(FBListApplicationsConfiguration.futureType);
    }];
}

@end
