/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBBinaryParser.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Concrete value wrapper around a binary artifact.
 */
@interface FBBinaryDescriptor : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param name The name of the executable. Must not be nil.
 @param architectures The supported architectures of the executable. Must not be nil.
 @param path The path to the executable. Must not be nil.
 @return a new FBBinaryDescriptor instance.
 */
- (instancetype)initWithName:(NSString *)name architectures:(NSSet<FBBinaryArchitecture> *)architectures path:(NSString *)path;

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
 The file path to the executable.
 */
@property (nonatomic, copy, readonly) NSString *path;

@end

NS_ASSUME_NONNULL_END
