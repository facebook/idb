// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

@interface FBMultiFileReader : NSObject

+ (instancetype)fileReader;
- (BOOL)addFileHandle:(NSFileHandle *)handle withConsumer:(void (^)(NSData *data))consumer error:(NSError **)error;
- (BOOL)readWhileBlockRuns:(void (^)())block error:(NSError **)error;

@end
