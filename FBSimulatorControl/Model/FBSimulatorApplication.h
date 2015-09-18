/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBDevice;

/**
 Concrete value wrapper around a binary artifact.
 */
@interface FBSimulatorBinary : NSObject<NSCopying>

/**
 Makes a Binary with the given parameters.

 @param name The name of the executable
 @param path The path to the executable.
 @param architectures The supported architectures of the executable.
 @returns a new FBSimulatorBinary instance.
 */
+ (instancetype)withName:(NSString *)name path:(NSString *)path architectures:(NSSet *)architectures;

/**
 The name of the executable.
 */
@property (nonatomic, readonly, copy) NSString *name;

/**
 The path to the executable.
 */
@property (nonatomic, readonly, copy) NSString *path;

/**
 The supported architectures of the executable.
 */
@property (nonatomic, readonly, copy) NSSet *architectures;

@end

/**
 Concrete value wrapper around a Application artifact.
 */
@interface FBSimulatorApplication : NSObject<NSCopying>

/**
 Make an Application with the given parameters.

 @param path The Path to the Application Bundle.
 @param bundleID the Bundle ID of the Application.
 @param binary the Path to the binary inside the Application.
 @returns a new FBSimulatorApplication instance.
 */
+ (instancetype)withName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(FBSimulatorBinary *)binary;

/**
 The name of the Application.
 */
@property (nonatomic, readonly, copy) NSString *name;

/**
 The path to the Application.
 */
@property (nonatomic, readonly, copy) NSString *path;

/**
 The Bundle Identifier of the app, i.e. com.Facebook for Wilde.
 */
@property (nonatomic, readonly, copy) NSString *bundleID;

/**
 The Binary contained within the Application
 */
@property (nonatomic, readonly, copy) FBSimulatorBinary *binary;

@end

/**
 Conveniences for building FBSimulatorApplication instances
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
 Constructing FBSimulatorApplication instances can be expensive, this method can be used to construct them in parallel.

 @param paths an Array of File Paths to build FBSimulatorApplication instances for.
 @returns an array of FBSimulatorApplication instances from the paths, NSNull.null for instances that could not be constructed.
 */
+ (NSArray *)simulatorApplicationsFromPaths:(NSArray *)paths;

/**
 Returns the FBSimulatorApplication for the current version of Xcode's Simulator.app

 @param error an error out.
 */
+ (instancetype)simulatorApplicationWithError:(NSError **)error;

/**
 Returns all of the FBSimulatorApplications for the System Applications on the Simulator
 */
+ (NSArray *)simulatorSystemApplications;

/**
 Returns the System Application with the provided name.

 @param appName the System Application to fetch.
 @returns FBSimulatorApplication instance if one could for the given name could be found, nil otherwise.
 */
+ (instancetype)systemApplicationNamed:(NSString *)appName;

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
