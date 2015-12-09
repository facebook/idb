/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

/**
 Concrete value wrapper around a binary artifact.
 */
@interface FBSimulatorBinary : NSObject <NSCopying, NSCoding>

/**
 The Designated Initializer.

 @param name The name of the executable. Must not be nil.
 @param path The path to the executable. Must not be nil.
 @param architectures The supported architectures of the executable. Must not be nil.
 @returns a new FBSimulatorBinary instance.
 */
- (instancetype)initWithName:(NSString *)name path:(NSString *)path architectures:(NSSet *)architectures;

/**
 An initializer for FBSimulatorBinary that checks the nullability of the arguments

 @param name The name of the executable. May be nil.
 @param path The path to the executable. May be nil.
 @param architectures The supported architectures of the executable. May be nil.
 @returns a new FBSimulatorBinary instance, if all arguments are non-nil.
 */
+ (instancetype)withName:(NSString *)name path:(NSString *)path architectures:(NSSet *)architectures;

/**
 The name of the executable.
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The path to the executable.
 */
@property (nonatomic, copy, readonly) NSString *path;

/**
 The supported architectures of the executable.
 */
@property (nonatomic, copy, readonly) NSSet *architectures;

@end

/**
 Concrete value wrapper around a Application artifact.
 */
@interface FBSimulatorApplication : NSObject <NSCopying, NSCoding>

/**
 The Designated Initializer.

 @param path The Path to the Application Bundle. Must not be nil.
 @param bundleID the Bundle ID of the Application. Must not be nil.
 @param binary the Path to the binary inside the Application. Must not be nil.
 @returns a new FBSimulatorApplication instance.
 */
- (instancetype)initWithName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(FBSimulatorBinary *)binary;

/**
 An initializer for FBSimulatorApplication that checks the nullability of the arguments

 @param path The Path to the Application Bundle. May be nil.
 @param bundleID the Bundle ID of the Application. May be nil.
 @param binary the Path to the binary inside the Application. May be nil.
 @returns a new FBSimulatorApplication instance, if all arguments are non-nil.
 */
+ (instancetype)withName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(FBSimulatorBinary *)binary;

/**
 The name of the Application.
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The path to the Application.
 */
@property (nonatomic, copy, readonly) NSString *path;

/**
 The Bundle Identifier of the app, i.e. com.Facebook for Wilde.
 */
@property (nonatomic, copy, readonly) NSString *bundleID;

/**
 The Binary contained within the Application
 */
@property (nonatomic, copy, readonly) FBSimulatorBinary *binary;

@end

/**
 Conveniences for building FBSimulatorApplication instances.
 */
@interface FBSimulatorApplication (Helpers)

/**
 Constructs a FBSimulatorApplication for the Application at the given path.

 @param path the path of the applocation to construct.
 @param error an error out.
 @returns a FBSimulatorApplication instance if one could be constructed, nil otherwise.
 */
+ (instancetype)applicationWithPath:(NSString *)path error:(NSError **)error;

/**
 Returns the FBSimulatorApplication for the current version of Xcode's Simulator.app

 @param error an error out.
 */
+ (instancetype)simulatorApplicationWithError:(NSError **)error;

/**
 Returns the System Application with the provided name.

 @param appName the System Application to fetch.
 @param error any error that occurred in fetching the application.
 @returns FBSimulatorApplication instance if one could for the given name could be found, nil otherwise.
 */
+ (instancetype)systemApplicationNamed:(NSString *)appName error:(NSError **)error;

@end

/**
 Conveniences for building FBSimulatorBinary instances
 */
@interface FBSimulatorBinary (Helpers)

/**
 Returns the FBSimulatorBinary for the given binary path
 */
+ (instancetype)binaryWithPath:(NSString *)path error:(NSError **)error;

@end
