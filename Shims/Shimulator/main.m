/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString *const ShimulatorCrashAfter = @"SHIMULATOR_CRASH_AFTER";
static NSString *const ShimulatorUploadVideo = @"SHIMULATOR_UPLOAD_VIDEO";

@interface VideoSaveDelegate : NSObject

@end

@implementation VideoSaveDelegate

static VideoSaveDelegate *delegate;

- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
  if (error) {
    NSLog(@"Couldn't save video with error %@", error);
  }
}

- (void)performAddVideo
{
  if (!NSProcessInfo.processInfo.environment[ShimulatorUploadVideo]) {
    return;
  }

  NSString *joinedFilePaths = NSProcessInfo.processInfo.environment[ShimulatorUploadVideo];
  NSArray *filePaths = [joinedFilePaths componentsSeparatedByString:@":"];

  NSLog(@"Adding videos at paths %@.", filePaths);

  [filePaths enumerateObjectsUsingBlock:^(NSString *filePath, NSUInteger _, BOOL *stop) {
    const BOOL success = [self addVideoAtPath:filePath];
    if (!success) {
      *stop = YES;
      NSLog(@"Failed to add video at path %@. Bailing out.", filePath);
    }
  }];

  NSLog(@"Finished adding videos");
}

- (BOOL)addVideoAtPath:(NSString *)path
{
  if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
    NSLog(@"Couldn't access video at path %@", path);
    return NO;
  }

  NSLog(@"Checking whether video at path %@ is compatible with the simulator", path);
  if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path)) {
    NSLog(@"Video not compatible at path %@", path);
    return NO;
  }

  delegate = [VideoSaveDelegate new];
  NSLog(@"Attempting to save video to photo album at path %@", path);
  UISaveVideoAtPathToSavedPhotosAlbum(path, delegate, @selector(video:didFinishSavingWithError:contextInfo:), nil);

  return YES;
}

@end

static void PerformCrashAfter(void)
{
  if (!NSProcessInfo.processInfo.environment[ShimulatorCrashAfter]) {
    return;
  }
  NSTimeInterval timeInterval = [NSProcessInfo.processInfo.environment[ShimulatorCrashAfter] doubleValue];
  NSLog(@"Forcing crash after %f seconds", timeInterval);
  [NSFileManager.defaultManager performSelector:@selector(stringWithFormat:) withObject:@"NOPE" afterDelay:timeInterval];
}

static void PerformAddVideo(void)
{
  delegate = [VideoSaveDelegate new];
  [delegate performSelector:@selector(performAddVideo) withObject:nil afterDelay:5];
}

__attribute__((constructor)) static void EntryPoint()
{
  NSLog(@"Start of Shimulator");

  PerformCrashAfter();
  PerformAddVideo();

  NSLog(@"End of Shimulator");
}
