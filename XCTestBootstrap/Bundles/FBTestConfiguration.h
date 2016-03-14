// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

@protocol FBFileManager;

/**
 Represents XCTestConfiguration class used by Apple to configure tests (aka .xctestconfiguration)
 */
@interface FBTestConfiguration : NSObject

/**
 The session identifier
 */
@property (nonatomic, copy, readonly) NSUUID *sessionIdentifier;

/**
 The name of the test module
 */
@property (nonatomic, copy, readonly) NSString *moduleName;

/**
 The path to test bundle
 */
@property (nonatomic, copy, readonly) NSString *testBundlePath;

/**
 The path to test configuration, if saved
 */
@property (nonatomic, copy, readonly) NSString *path;

@end


/**
 Creates FBTestConfiguration by:
 - creating object with requested values
 - saving it, if saveAs is set
 */
@interface FBTestConfigurationBuilder : NSObject

/**
 @return builder that uses [NSFileManager defaultManager] as file manager
 */
+ (instancetype)builder;

/**
 @param fileManager a file manager used with builder
 @return builder
 */
+ (instancetype)builderWithFileManager:(id<FBFileManager>)fileManager;

/**
 @param sessionIdentifier test session identifer
 @return builder
 */
- (instancetype)withSessionIdentifier:(NSUUID *)sessionIdentifier;

/**
 @param moduleName test module name
 @return builder
 */
- (instancetype)withModuleName:(NSString *)moduleName;

/**
 @param testBundlePath path to test bundle
 @return builder
 */
- (instancetype)withTestBundlePath:(NSString *)testBundlePath;

/**
 @param savePath is set, builder will save file at given path that can be loaded directly by XCTestConfiguration
 @return builder
 */
- (instancetype)saveAs:(NSString *)savePath;

/**
 @return test configuration
 */
- (FBTestConfiguration *)build;

@end
