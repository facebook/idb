// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBLineReader.h"

@interface FBLineReader ()

@property (nonatomic, copy, readonly) void (^consumer)(NSString *);
@property (nonatomic, strong, readonly) NSMutableData *buffer;

@end

@implementation FBLineReader

+ (instancetype)lineReaderWithConsumer:(void (^)(NSString *))consumer
{
  return [[self alloc] initWithConsumer:consumer];
}

- (instancetype)initWithConsumer:(void (^)(NSString *))consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _buffer = [NSMutableData data];

  return self;
}

- (void)consumeData:(NSData *)data
{
  [self.buffer appendData:data];
  while (self.buffer.length != 0) {
    NSRange newlineRange = [self.buffer rangeOfData:[NSData dataWithBytes:"\n" length:1]
                                            options:0
                                              range:NSMakeRange(0, self.buffer.length)];
    if (newlineRange.length == 0) {
      break;
    }
    NSData *lineData = [self.buffer subdataWithRange:NSMakeRange(0, newlineRange.location)];
    [self.buffer replaceBytesInRange:NSMakeRange(0, newlineRange.location + 1) withBytes:"" length:0];
    NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
    self.consumer(line);
  }
}

- (void)consumeEndOfFile
{
  if (self.buffer.length != 0) {
    NSString *line = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
    self.consumer(line);
    self.buffer.data = [NSData data];
  }
}

@end
