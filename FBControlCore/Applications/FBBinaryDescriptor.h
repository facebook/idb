/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString *FBBinaryArchitecture NS_STRING_ENUM;

extern FBBinaryArchitecture const FBBinaryArchitecturei386;
extern FBBinaryArchitecture const FBBinaryArchitecturex86_64;
extern FBBinaryArchitecture const FBBinaryArchitectureArm;
extern FBBinaryArchitecture const FBBinaryArchitectureArm64;

/**
 Concrete value wrapper around a binary artifact.
 */
@interface FBBinaryDescriptor : NSObject <NSCopying>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param name The name of the executable. Must not be nil.
 @param architectures The supported architectures of the executable. Must not be nil.
 @param uuid the LC_UUID of the binary.
 @param path The path to the executable. Must not be nil.
 @return a new FBBinaryDescriptor instance.
 */
- (instancetype)initWithName:(NSString *)name architectures:(NSSet<FBBinaryArchitecture> *)architectures uuid:(nullable NSUUID *)uuid path:(NSString *)path;

/**
 Returns the FBBinaryDescriptor for the given binary path, by parsing the binary.

 @param path the path to the binary.
 @param error an error out for any error that occurs.
 @return a Binary Descriptor, if one could be parsed.
 */
+ (nullable instancetype)binaryWithPath:(NSString *)path error:(NSError **)error;

#pragma mark Properties

/**
 The name of the executable.
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The Supported Architectures of the Executable.
 */
@property (nonatomic, copy, readonly) NSSet<FBBinaryArchitecture> *architectures;

/**
 The LC_UUID of the binary (if present)
 */
@property (nonatomic, copy, nullable, readonly) NSUUID *uuid;

/**
 The file path to the executable.
 */
@property (nonatomic, copy, readonly) NSString *path;

#pragma mark Public Methods

/**
 Obtain the rpaths in the binary.
 */
- (nullable NSArray<NSString *> *)rpathsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
