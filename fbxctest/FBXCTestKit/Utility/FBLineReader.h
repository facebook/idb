// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

@interface FBLineReader : NSObject

+ (instancetype)lineReaderWithConsumer:(void (^)(NSString *))consumer;
- (void)consumeData:(NSData *)data;
- (void)consumeEndOfFile;

@end
