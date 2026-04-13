/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>

/**
 An enumeration representing the existing file containers.
 */
typedef NSString *FBFileContainerKind NS_STRING_ENUM;
extern FBFileContainerKind _Nonnull const FBFileContainerKindApplication;
extern FBFileContainerKind _Nonnull const FBFileContainerKindAuxillary;
extern FBFileContainerKind _Nonnull const FBFileContainerKindCrashes;
extern FBFileContainerKind _Nonnull const FBFileContainerKindDiskImages;
extern FBFileContainerKind _Nonnull const FBFileContainerKindGroup;
extern FBFileContainerKind _Nonnull const FBFileContainerKindMDMProfiles;
extern FBFileContainerKind _Nonnull const FBFileContainerKindMedia;
extern FBFileContainerKind _Nonnull const FBFileContainerKindProvisioningProfiles;
extern FBFileContainerKind _Nonnull const FBFileContainerKindRoot;
extern FBFileContainerKind _Nonnull const FBFileContainerKindSpringboardIcons;
extern FBFileContainerKind _Nonnull const FBFileContainerKindSymbols;
extern FBFileContainerKind _Nonnull const FBFileContainerKindWallpaper;
extern FBFileContainerKind _Nonnull const FBFileContainerKindXctest;
extern FBFileContainerKind _Nonnull const FBFileContainerKindDylib;
extern FBFileContainerKind _Nonnull const FBFileContainerKindDsym;
extern FBFileContainerKind _Nonnull const FBFileContainerKindFramework;

@protocol FBDataConsumer;
@protocol FBProvisioningProfileCommands;

/**
 Implementations of File Commands.
 */
@interface FBFileContainer : NSObject

+ (nonnull id)fileContainerForProvisioningProfileCommands:(nonnull id<FBProvisioningProfileCommands>)commands queue:(nonnull dispatch_queue_t)queue;
+ (nonnull id)containedFileForBasePath:(nonnull NSString *)basePath;
+ (nonnull id)containedFileForPathMapping:(nonnull NSDictionary<NSString *, NSString *> *)pathMapping;
+ (nonnull id)fileContainerForBasePath:(nonnull NSString *)basePath;
+ (nonnull id)fileContainerForPathMapping:(nonnull NSDictionary<NSString *, NSString *> *)pathMapping;
+ (nonnull id)fileContainerForContainedFile:(nonnull id)containedFile;

@end
