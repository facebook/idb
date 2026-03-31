/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFileContainer.h>

/**
 Helper to work around Swift's inability to handle ObjC classes and protocols
 that share the same name (FBFileContainer/FBFileContainerProtocol).
 This class conforms to the FBFileContainerProtocol protocol and delegates to an
 underlying container, making the protocol methods accessible from Swift.
 */
@interface FBFileContainerTestHelpers : NSObject

+ (nonnull FBFileContainerTestHelpers *)containerForBasePath:(nonnull NSString *)basePath;
+ (nonnull FBFileContainerTestHelpers *)containerForPathMapping:(nonnull NSDictionary<NSString *, NSString *> *)pathMapping;

- (nonnull FBFuture<NSNull *> *)copyFromHost:(nonnull NSString *)sourcePath toContainer:(nonnull NSString *)destinationPath;
- (nonnull FBFuture<NSString *> *)copyFromContainer:(nonnull NSString *)sourcePath toHost:(nonnull NSString *)destinationPath;
- (nonnull FBFuture<NSNull *> *)createDirectory:(nonnull NSString *)directoryPath;
- (nonnull FBFuture<NSNull *> *)moveFrom:(nonnull NSString *)sourcePath to:(nonnull NSString *)destinationPath;
- (nonnull FBFuture<NSNull *> *)remove:(nonnull NSString *)path;
- (nonnull FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(nonnull NSString *)path;

@end
