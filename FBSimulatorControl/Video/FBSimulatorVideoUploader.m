/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorVideoUploader.h"

#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBSimulatorSession.h"
#import "FBSimulatorSessionInteraction.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@interface FBSimulatorVideoUploader()

@property (nonatomic, strong, readwrite) FBSimulatorSession *session;

@end

@implementation FBSimulatorVideoUploader

+ (instancetype)forSession:(FBSimulatorSession *)session
{
  FBSimulatorVideoUploader *uploader = [self new];
  uploader.session = session;
  return uploader;
}

- (BOOL)uploadVideos:(NSArray *)videoPaths error:(NSError **)error
{
  if (!videoPaths.count) {
    return YES;
  }

  FBSimulatorSession *session = self.session;
  FBSimulator *simulator = session.simulator;
  NSString *dcimPath = [simulator.dataDirectory stringByAppendingPathComponent:@"Media/DCIM/100APPLE"];
  NSArray *dcimPaths = ({
    NSError *innerError = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *subpaths = [fileManager subpathsOfDirectoryAtPath:dcimPath error:&innerError];
    if (!subpaths) {
      return [[[FBSimulatorError describeFormat:@"Couldn't read DCIM directory at path %@", dcimPath]
        causedBy:innerError]
        failBool:error];
    }
    [subpaths filteredArrayUsingPredicate:[self.class predicateForVideoFiles]];
  });

  NSString *joinedPaths = [videoPaths componentsJoinedByString:@":"];

  FBSimulatorApplication *photosApp = [FBSimulatorApplication systemApplicationNamed:@"MobileSlideShow"];

  FBApplicationLaunchConfiguration *appLaunch = [[FBApplicationLaunchConfiguration
    configurationWithApplication:photosApp
    arguments:@[]
    environment:@{@"SHIMULATOR_UPLOAD_VIDEO" : joinedPaths}]
    injectingShimulator];

  {
    NSError *innerError = nil;
    if (![[session.interact launchApplication:appLaunch] performInteractionWithError:&innerError]) {
      return [[[FBSimulatorError describe:@"Couldn't launch MobileSlideShow to upload videos"]
        causedBy:innerError]
        failBool:error];
    }
  }

  const BOOL success = [self.class waitUntilFileCount:videoPaths.count
                                     addedToDirectory:dcimPath
                                        previousCount:dcimPaths.count
                                                error:error];

  {
    NSError *innerError = nil;
    if (![[self.session.interact killApplication:photosApp] performInteractionWithError:nil]) {
      return [[[FBSimulatorError describe:@"Couldn't kill MobileSlideShow after uploading videos"]
        causedBy:innerError]
        failBool:error];
    }
  }

  return success;
}

#pragma mark - Private

+ (BOOL)waitUntilFileCount:(NSInteger)fileCount
          addedToDirectory:(NSString *)directory
             previousCount:(NSInteger)previousCount
                     error:(NSError **)error
{
  static NSTimeInterval const UploadVideoDefaultWait = 15.0;

  NSFileManager *fileManager = [NSFileManager defaultManager];
  __block NSError *innerError = nil;
  const BOOL success = [NSRunLoop.currentRunLoop
                        spinRunLoopWithTimeout:UploadVideoDefaultWait
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
