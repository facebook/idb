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
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "Runtime/PhotoLibraryClient.h"
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

int FBPhotoLibraryClearWithLibrary(PHPhotoLibrary *photoLibrary, PHFetchResult<PHAsset *> *allPhotos)
{
  FBPhotoLibraryClient *client = [FBPhotoLibraryClient makeWithPhotoLibrary:photoLibrary assets:allPhotos];
  if (!client) {
    return 1;
  }
  return (int)[FBPhotoLibraryService clearWithClient:client];
}

int handlePhotoLibraryAction(NSString *action)
{
  return (int)[FBPhotoLibraryService handlePhotoLibraryAction:action ?: @"(null)"];
}
