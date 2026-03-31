/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFileContainer.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Helper to work around Swift's inability to handle ObjC classes and protocols
 that share the same name (FBFileContainer).
 This class conforms to the FBFileContainer protocol and delegates to an
 underlying container, making the protocol methods accessible from Swift.
 */
@interface FBFileContainerTestHelpers : NSObject

+ (FBFileContainerTestHelpers *)containerForBasePath:(NSString *)basePath;
+ (FBFileContainerTestHelpers *)containerForPathMapping:(NSDictionary<NSString *, NSString *> *)pathMapping;

- (FBFuture<NSNull *> *)copyFromHost:(NSString *)sourcePath toContainer:(NSString *)destinationPath;
- (FBFuture<NSString *> *)copyFromContainer:(NSString *)sourcePath toHost:(NSString *)destinationPath;
- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath;
- (FBFuture<NSNull *> *)moveFrom:(NSString *)sourcePath to:(NSString *)destinationPath;
- (FBFuture<NSNull *> *)remove:(NSString *)path;
- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
