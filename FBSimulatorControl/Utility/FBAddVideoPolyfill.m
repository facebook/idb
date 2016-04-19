/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAddVideoPolyfill.h"

#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorInteraction+Applications.h"
#import "FBSimulatorInteraction+Lifecycle.h"

@interface FBAddVideoPolyfill ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBAddVideoPolyfill

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark Public

- (BOOL)addVideos:(NSArray *)paths error:(NSError **)error
{
  return [FBAddVideoPolyfill uploadVideos:paths simulator:self.simulator error:error];
}

#pragma mark Private

+ (BOOL)uploadVideos:(NSArray *)videoPaths simulator:(FBSimulator *)simulator error:(NSError **)error
{
  if (!videoPaths.count) {
    return YES;
  }

  NSString *dcimPath = [simulator.dataDirectory stringByAppendingPathComponent:@"Media/DCIM/100APPLE"];
  NSArray *dcimPaths = ({
    NSError *innerError = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *subpaths = [fileManager subpathsOfDirectoryAtPath:dcimPath error:&innerError];
    if (!subpaths) {
      return [[[FBSimulatorError
        describeFormat:@"Couldn't read DCIM directory at path %@", dcimPath]
        causedBy:innerError]
        failBool:error];
    }
    [subpaths filteredArrayUsingPredicate:[self.class predicateForVideoFiles]];
  });

  NSString *joinedPaths = [videoPaths componentsJoinedByString:@":"];

  NSError *innerError = nil;
  FBSimulatorApplication *photosApp = [FBSimulatorApplication systemApplicationNamed:@"MobileSlideShow" error:&innerError];
  if (!photosApp) {
    return [[[FBSimulatorError
      describe:@"Could not get the MobileSlideShow App"]
      causedBy:innerError]
      failBool:error];
  }

  FBApplicationLaunchConfiguration *appLaunch = [[FBApplicationLaunchConfiguration
    configurationWithApplication:photosApp
    arguments:@[]
    environment:@{@"SHIMULATOR_UPLOAD_VIDEO" : joinedPaths}
    options:0]
    injectingShimulator];

  if (![[simulator.interact launchApplication:appLaunch] perform:&innerError]) {
    return [[[FBSimulatorError describe:@"Couldn't launch MobileSlideShow to upload videos"]
      causedBy:innerError]
      failBool:error];
  }

  BOOL success = [self.class
    waitUntilFileCount:videoPaths.count
    addedToDirectory:dcimPath
    previousCount:dcimPaths.count
    error:error];

  FBProcessInfo *photosAppProcess = simulator.history.lastLaunchedApplicationProcess;
  if (![photosAppProcess.processName isEqualToString:@"MobileSlideshow"]) {
    return [[[FBSimulatorError
      describe:@"Couldn't find MobileSlideShow process after uploading video"]
      causedBy:innerError]
      failBool:error];
  }

  if (![[simulator.interact killProcess:photosAppProcess] perform:nil]) {
    return [[[FBSimulatorError
      describe:@"Couldn't kill MobileSlideShow after uploading videos"]
      causedBy:innerError]
      failBool:error];
  }

  return success;
}

+ (BOOL)waitUntilFileCount:(NSUInteger)fileCount addedToDirectory:(NSString *)directory previousCount:(NSUInteger)previousCount error:(NSError **)error
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  __block NSError *innerError = nil;
  const BOOL success = [NSRunLoop.currentRunLoop
    spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout
    untilTrue:^ BOOL {
      NSArray *paths = [fileManager subpathsOfDirectoryAtPath:directory error:&innerError];
      paths = [paths filteredArrayUsingPredicate:[self.class predicateForVideoFiles]];
      return paths.count == fileCount + previousCount;
    }];

  if (!success) {
    return [[[FBSimulatorError describeFormat:@"Failed to upload videos"] causedBy:innerError] failBool:error];
  }

  return YES;
}

+ (NSPredicate *)predicateForVideoFiles
{
  return [NSPredicate predicateWithFormat:@"pathExtension IN %@", @[@"mp4"]];
}

@end
