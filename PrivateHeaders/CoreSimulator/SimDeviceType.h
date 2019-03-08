/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@class NSArray, NSBundle, NSDictionary, NSString;

@interface SimDeviceType : NSObject
{
    float _mainScreenScale;
    unsigned int _minRuntimeVersion;
    unsigned int _maxRuntimeVersion;
    unsigned int _minCoreSimulatorFrameworkVersion;
    unsigned int _maxCoreSimulatorFrameworkVersion;
    NSString *_name;
    NSString *_identifier;
    NSString *_modelIdentifier;
    NSBundle *_bundle;
    NSArray *_supportedArchs;
    NSArray *_supportedProductFamilyIDs;
    NSDictionary *_capabilities;
    NSString *_springBoardConfigName;
    NSString *_productClass;
    NSDictionary *_environment_extra;
    NSArray *_aliases;
    NSDictionary *_supportedFeatures;
    NSDictionary *_supportedFeaturesConditionalOnRuntime;
    struct CGSize _mainScreenSize;
    struct CGSize _mainScreenDPI;
}

@property (copy, nonatomic) NSDictionary *supportedFeaturesConditionalOnRuntime;
@property (copy, nonatomic) NSDictionary *supportedFeatures;
@property (copy, nonatomic) NSArray *aliases;
@property (copy, nonatomic) NSDictionary *environment_extra;
@property (copy, nonatomic) NSString *productClass;
@property (copy, nonatomic) NSString *springBoardConfigName;
@property (nonatomic, assign) unsigned int maxCoreSimulatorFrameworkVersion;
@property (nonatomic, assign) unsigned int minCoreSimulatorFrameworkVersion;
@property (nonatomic, assign) unsigned int maxRuntimeVersion;
@property (nonatomic, assign) unsigned int minRuntimeVersion;
@property (nonatomic, assign) struct CGSize mainScreenDPI;
@property (nonatomic, assign) struct CGSize mainScreenSize;
@property (copy, nonatomic) NSDictionary *capabilities;
@property (nonatomic, assign) float mainScreenScale;
@property (copy, nonatomic) NSArray *supportedProductFamilyIDs;
@property (copy, nonatomic) NSArray *supportedArchs;
@property (retain, nonatomic) NSBundle *bundle;
@property (copy, nonatomic) NSString *modelIdentifier;
@property (copy, nonatomic) NSString *identifier;
@property (copy, nonatomic) NSString *name;

- (Class)deviceClass;
- (long long)compare:(id)arg1;
- (BOOL)supportsFeatureConditionally:(id)arg1;
- (BOOL)supportsFeature:(id)arg1;
- (id)environment;
@property (nonatomic, copy, readonly) NSString *productFamily;
@property (readonly, nonatomic) int productFamilyID;
- (id)description;
- (id)initWithBundle:(id)arg1;
- (id)initWithPath:(id)arg1;

@end
