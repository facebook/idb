/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "PhotoLibraryService.h"
#import "PhotoLibraryService+Testing.h"

#if __has_include(<SimulatorFrameworkBridgeRuntime/PhotoLibraryClient.h>)
 #import <SimulatorFrameworkBridgeRuntime/PhotoLibraryClient.h>
#else
 #import "Runtime/PhotoLibraryClient.h"
#endif

int FBPhotoLibraryClearWithLibrary(PHPhotoLibrary *photoLibrary, PHFetchResult<PHAsset *> *allPhotos)
{
  @try {
    FBPhotoLibraryClient *client = [[FBPhotoLibraryClient alloc] initWithPhotoLibrary:photoLibrary assets:allPhotos];
    if (client.assetCount == 0) {
      NSLog(@"No photos to delete");
      return 0;
    }
    NSLog(@"Found %lu photos to delete", (unsigned long)client.assetCount);
    return [client deleteAssets] ? 0 : 1;
  } @catch (NSException *exception) {
    NSLog(@"Failed to clear photo library: %@", exception);
    return 1;
  }
}

int handlePhotoLibraryAction(NSString *action)
{
  if ([action isEqualToString:@"clear"]) {
    PHPhotoLibrary *library = [PHPhotoLibrary sharedPhotoLibrary];
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    return FBPhotoLibraryClearWithLibrary(library, [PHAsset fetchAssetsWithOptions:options]);
  } else {
    NSLog(@"Unknown action: %@", action);
    return 1;
  }
}
