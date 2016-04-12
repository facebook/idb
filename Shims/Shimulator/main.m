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
static NSString *const ShimulatorCleanKeychain = @"SHIMULATOR_CLEAN_KEYCHAIN";

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

static BOOL VerifyNoAppKeychainItems(void);
static NSArray *SecItemClasses(void);

static void KillAppAndCleanKeychain(void)
{
    if (!NSProcessInfo.processInfo.environment[ShimulatorCleanKeychain]) {
      NSLog(@"Not clearing keychain");
      return;
    }

    NSLog(@"Attempting to clean keychain");
    for (NSString *secItemClass in SecItemClasses()) {
      NSDictionary *spec = @{(__bridge NSString *)kSecClass: secItemClass};
      NSLog(@"Removing all keychain items for keychain class %@", secItemClass);
      OSStatus ret = SecItemDelete((__bridge CFDictionaryRef)spec);
      if (ret == errSecSuccess || ret == errSecItemNotFound) {
        NSLog(@"Successfully removed all keychain items for keychain class %@", secItemClass);
      } else {
        NSLog(@"Failed to remove all keychain items for keychain class %@", secItemClass);
      }
    }

    if (!VerifyNoAppKeychainItems()) {
      NSLog(@"Failed to remove all keychain items. Killing app");
      // Kill app.
      exit(0);
    } else {
      NSLog(@"Succeeded in removing all keychain items");
    }
}

static BOOL VerifyNoAppKeychainItems(void)
{
    NSDictionary *baseQuery = @{
      (__bridge id)kSecReturnAttributes:(__bridge id)kCFBooleanTrue,
      (__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitAll,
    };
    for (NSString *secItemClass in SecItemClasses()) {
      NSMutableDictionary *query = [baseQuery mutableCopy];
      query[(__bridge NSString *)kSecClass]] = secItemClass;
      CFTypeRef result = NULL;
      OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
      if (result != NULL) {
        CFRelease(result);
      }
      if (status == errSecSuccess) {
        NSLog(@"Loaded keychain item of type %@", secItemClass);
        return NO;
      }
    }
    return YES;
}

static NSArray<NSString *> *SecItemClasses(void)
{
  return @[
    (__bridge NSString *)kSecClassGenericPassword,
    (__bridge NSString *)kSecClassInternetPassword,
    (__bridge NSString *)kSecClassCertificate,
    (__bridge NSString *)kSecClassKey,
    (__bridge NSString *)kSecClassIdentity,
  ];
}

__attribute__((constructor)) static void EntryPoint()
{
  NSLog(@"Start of Shimulator");

  PerformCrashAfter();
  PerformAddVideo();
  KillAppAndCleanKeychain();

  NSLog(@"End of Shimulator");
}
