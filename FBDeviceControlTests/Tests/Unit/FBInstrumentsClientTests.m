/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceControl.h>

// Constants mirroring private definitions in FBInstrumentsClient.m
static const uint64_t TestArgumentMagic = 0x1F0;
static const uint32_t TestEmptyDictionaryKey = 10;
static const uint32_t TestObjectArgumentType = 2;
static const uint32_t TestInt32ArgumentType = 3;

#pragma mark - Private Method Exposure

@interface FBInstrumentsClient (Testing)

+ (NSData *)argumentDataForArgument:(id)argument;
+ (NSData *)argumentDataForInt32:(int32_t)value;
+ (NSData *)auxillaryDataFromArgumentsData:(nullable NSArray<NSData *> *)arguments;
+ (NSArray<id> *)objectArgumentsFromAuxillaryData:(NSData *)data error:(NSError **)error;
+ (NSData *)advanceData:(NSData *)data buffer:(void *)buffer length:(size_t)length;
+ (NSData *)advanceData:(NSData *)data dataOut:(NSData **)dataOut length:(size_t)length;

@end

#pragma mark - Test Class

@interface FBInstrumentsClientTests : XCTestCase
@end

@implementation FBInstrumentsClientTests

#pragma mark - argumentDataForArgument: Tests

- (void)testArgumentDataForArgument_WithString_ProducesValidSerializedData
{
  NSString *argument = @"com.example.testapp";

  NSData *result = [FBInstrumentsClient argumentDataForArgument:argument];

  XCTAssertNotNil(result, @"Result should not be nil for a valid string argument");
  XCTAssertGreaterThan(result.length, (NSUInteger)12, @"Result should be larger than the 12-byte header");

  uint32_t dictionaryKey = 0;
  uint32_t argumentType = 0;
  uint32_t argumentSize = 0;
  [result getBytes:&dictionaryKey range:NSMakeRange(0, sizeof(uint32_t))];
  [result getBytes:&argumentType range:NSMakeRange(4, sizeof(uint32_t))];
  [result getBytes:&argumentSize range:NSMakeRange(8, sizeof(uint32_t))];

  XCTAssertEqual(dictionaryKey, TestEmptyDictionaryKey, @"Dictionary key should match expected constant");
  XCTAssertEqual(argumentType, TestObjectArgumentType, @"Argument type should be ObjectArgumentType (2)");
  XCTAssertEqual((NSUInteger)argumentSize, result.length - 12, @"Argument size should match remaining data length");

  NSData *archivedData = [result subdataWithRange:NSMakeRange(12, argumentSize)];
  NSError *error = nil;
  NSString *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:archivedData error:&error];
  XCTAssertNil(error, @"Unarchiving should not produce an error");
  XCTAssertEqualObjects(decoded, argument, @"Decoded value should match the original argument");
}

- (void)testArgumentDataForArgument_WithDictionary_ProducesValidSerializedData
{
  NSDictionary *argument = @{@"StartSuspendedKey" : @YES, @"KillExisting" : @NO};

  NSData *result = [FBInstrumentsClient argumentDataForArgument:argument];

  XCTAssertNotNil(result);
  XCTAssertGreaterThan(result.length, (NSUInteger)12);

  uint32_t argumentSize = 0;
  [result getBytes:&argumentSize range:NSMakeRange(8, sizeof(uint32_t))];

  NSData *archivedData = [result subdataWithRange:NSMakeRange(12, argumentSize)];
  NSError *error = nil;
  NSDictionary *decoded = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithArray:@[NSDictionary.class, NSNumber.class, NSString.class]] fromData:archivedData error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(decoded, argument, @"Decoded dictionary should match the original");
}

- (void)testArgumentDataForArgument_WithEmptyString_ProducesValidSerializedData
{
  NSString *argument = @"";

  NSData *result = [FBInstrumentsClient argumentDataForArgument:argument];

  XCTAssertNotNil(result);
  XCTAssertGreaterThan(result.length, (NSUInteger)12);

  uint32_t argumentSize = 0;
  [result getBytes:&argumentSize range:NSMakeRange(8, sizeof(uint32_t))];

  NSData *archivedData = [result subdataWithRange:NSMakeRange(12, argumentSize)];
  NSError *error = nil;
  NSString *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:archivedData error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(decoded, @"", @"Decoded string should be empty");
}

#pragma mark - argumentDataForInt32: Tests

- (void)testArgumentDataForInt32_WithPositiveValue_ProducesCorrectFormat
{
  int32_t value = 42;

  NSData *result = [FBInstrumentsClient argumentDataForInt32:value];

  XCTAssertEqual(result.length, (NSUInteger)12, @"Int32 argument data should be exactly 12 bytes");

  uint32_t dictionaryKey = 0;
  uint32_t argumentType = 0;
  int32_t decodedValue = 0;
  [result getBytes:&dictionaryKey range:NSMakeRange(0, sizeof(uint32_t))];
  [result getBytes:&argumentType range:NSMakeRange(4, sizeof(uint32_t))];
  [result getBytes:&decodedValue range:NSMakeRange(8, sizeof(int32_t))];

  XCTAssertEqual(dictionaryKey, TestEmptyDictionaryKey, @"Dictionary key should match");
  XCTAssertEqual(argumentType, TestInt32ArgumentType, @"Type should be Int32ArgumentType (3)");
  XCTAssertEqual(decodedValue, 42, @"Decoded value should match the original");
}

- (void)testArgumentDataForInt32_WithNegativeValue_PreservesSign
{
  int32_t value = -1;

  NSData *result = [FBInstrumentsClient argumentDataForInt32:value];

  XCTAssertEqual(result.length, (NSUInteger)12);

  int32_t decodedValue = 0;
  [result getBytes:&decodedValue range:NSMakeRange(8, sizeof(int32_t))];
  XCTAssertEqual(decodedValue, -1, @"Negative value should be preserved");
}

- (void)testArgumentDataForInt32_WithZero_ProducesCorrectFormat
{
  NSData *result = [FBInstrumentsClient argumentDataForInt32:0];

  XCTAssertEqual(result.length, (NSUInteger)12);

  int32_t decodedValue = 1;
  [result getBytes:&decodedValue range:NSMakeRange(8, sizeof(int32_t))];
  XCTAssertEqual(decodedValue, 0, @"Zero value should be preserved");
}

- (void)testArgumentDataForInt32_WithMaxValue_PreservesBoundary
{
  int32_t value = INT32_MAX;

  NSData *result = [FBInstrumentsClient argumentDataForInt32:value];

  int32_t decodedValue = 0;
  [result getBytes:&decodedValue range:NSMakeRange(8, sizeof(int32_t))];
  XCTAssertEqual(decodedValue, INT32_MAX, @"INT32_MAX should be preserved");
}

#pragma mark - auxillaryDataFromArgumentsData: Tests

- (void)testAuxillaryDataFromArgumentsData_WithNilArguments_ReturnsEmptyData
{
  NSData *result = [FBInstrumentsClient auxillaryDataFromArgumentsData:nil];

  XCTAssertNotNil(result);
  XCTAssertEqual(result.length, (NSUInteger)0, @"Nil arguments should produce empty data");
}

- (void)testAuxillaryDataFromArgumentsData_WithSingleArgument_IncludesMagicAndLength
{
  NSData *argData = [FBInstrumentsClient argumentDataForArgument:@"test"];

  NSData *result = [FBInstrumentsClient auxillaryDataFromArgumentsData:@[argData]];

  XCTAssertNotNil(result);
  XCTAssertEqual(result.length, (NSUInteger)(16 + argData.length), @"Result should be header (16) + argument data");

  uint64_t magic = 0;
  uint64_t payloadLength = 0;
  [result getBytes:&magic range:NSMakeRange(0, sizeof(uint64_t))];
  [result getBytes:&payloadLength range:NSMakeRange(8, sizeof(uint64_t))];

  XCTAssertEqual(magic, TestArgumentMagic, @"Magic should match ArgumentMagic constant (0x1F0)");
  XCTAssertEqual(payloadLength, (uint64_t)argData.length, @"Payload length should match argument data length");
}

- (void)testAuxillaryDataFromArgumentsData_WithMultipleArguments_ConcatenatesCorrectly
{
  NSData *arg1 = [FBInstrumentsClient argumentDataForArgument:@"first"];
  NSData *arg2 = [FBInstrumentsClient argumentDataForArgument:@"second"];

  NSData *result = [FBInstrumentsClient auxillaryDataFromArgumentsData:@[arg1, arg2]];

  uint64_t payloadLength = 0;
  [result getBytes:&payloadLength range:NSMakeRange(8, sizeof(uint64_t))];
  XCTAssertEqual(payloadLength, (uint64_t)(arg1.length + arg2.length), @"Payload length should be sum of all argument lengths");
  XCTAssertEqual(result.length, (NSUInteger)(16 + arg1.length + arg2.length));
}

- (void)testAuxillaryDataFromArgumentsData_WithEmptyArray_ProducesHeaderOnly
{
  NSData *result = [FBInstrumentsClient auxillaryDataFromArgumentsData:@[]];

  XCTAssertEqual(result.length, (NSUInteger)16, @"Empty array should produce header-only data (16 bytes)");

  uint64_t payloadLength = 0;
  [result getBytes:&payloadLength range:NSMakeRange(8, sizeof(uint64_t))];
  XCTAssertEqual(payloadLength, (uint64_t)0, @"Payload length should be zero for empty array");
}

#pragma mark - objectArgumentsFromAuxillaryData:error: Tests

- (void)testObjectArgumentsFromAuxillaryData_RoundTrip_WithSingleString
{
  NSData *argData = [FBInstrumentsClient argumentDataForArgument:@"hello"];
  NSData *auxData = [FBInstrumentsClient auxillaryDataFromArgumentsData:@[argData]];

  NSError *error = nil;
  NSArray<id> *result = [FBInstrumentsClient objectArgumentsFromAuxillaryData:auxData error:&error];

  XCTAssertNil(error, @"Round-trip should not produce an error");
  XCTAssertNotNil(result);
  XCTAssertEqual(result.count, (NSUInteger)1, @"Should contain exactly one argument");
  XCTAssertEqualObjects(result[0], @"hello", @"Decoded argument should match original");
}

- (void)testObjectArgumentsFromAuxillaryData_RoundTrip_WithMultipleArguments
{
  NSData *arg1 = [FBInstrumentsClient argumentDataForArgument:@"first"];
  NSData *arg2 = [FBInstrumentsClient argumentDataForArgument:@(42)];
  NSData *auxData = [FBInstrumentsClient auxillaryDataFromArgumentsData:@[arg1, arg2]];

  NSError *error = nil;
  NSArray<id> *result = [FBInstrumentsClient objectArgumentsFromAuxillaryData:auxData error:&error];

  XCTAssertNil(error);
  XCTAssertEqual(result.count, (NSUInteger)2);
  XCTAssertEqualObjects(result[0], @"first");
  XCTAssertEqualObjects(result[1], @(42));
}

- (void)testObjectArgumentsFromAuxillaryData_WithInsufficientData_ReturnsError
{
  uint8_t shortBytes[] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05};
  NSData *shortData = [NSData dataWithBytes:shortBytes length:sizeof(shortBytes)];

  NSError *error = nil;
  NSArray<id> *result = [FBInstrumentsClient objectArgumentsFromAuxillaryData:shortData error:&error];

  XCTAssertNil(result, @"Should return nil for insufficient data");
  XCTAssertNotNil(error, @"Should produce an error for insufficient data");
}

- (void)testObjectArgumentsFromAuxillaryData_RoundTrip_WithDictionary
{
  NSDictionary *dict = @{@"key" : @"value", @"number" : @(123)};
  NSData *argData = [FBInstrumentsClient argumentDataForArgument:dict];
  NSData *auxData = [FBInstrumentsClient auxillaryDataFromArgumentsData:@[argData]];

  NSError *error = nil;
  NSArray<id> *result = [FBInstrumentsClient objectArgumentsFromAuxillaryData:auxData error:&error];

  XCTAssertNil(error);
  XCTAssertEqual(result.count, (NSUInteger)1);
  XCTAssertEqualObjects(result[0], dict, @"Decoded dictionary should match original");
}

- (void)testObjectArgumentsFromAuxillaryData_PreservesArgumentOrder
{
  NSData *arg1 = [FBInstrumentsClient argumentDataForArgument:@"alpha"];
  NSData *arg2 = [FBInstrumentsClient argumentDataForArgument:@"beta"];
  NSData *arg3 = [FBInstrumentsClient argumentDataForArgument:@"gamma"];
  NSData *auxData = [FBInstrumentsClient auxillaryDataFromArgumentsData:@[arg1, arg2, arg3]];

  NSError *error = nil;
  NSArray<id> *result = [FBInstrumentsClient objectArgumentsFromAuxillaryData:auxData error:&error];

  XCTAssertNil(error);
  XCTAssertEqual(result.count, (NSUInteger)3);
  XCTAssertEqualObjects(result[0], @"alpha", @"First argument should be alpha");
  XCTAssertEqualObjects(result[1], @"beta", @"Second argument should be beta");
  XCTAssertEqualObjects(result[2], @"gamma", @"Third argument should be gamma");
}

#pragma mark - advanceData: Tests

- (void)testAdvanceData_WithBuffer_ReadsCorrectBytesAndAdvances
{
  uint32_t values[] = {0xDEADBEEF, 0xCAFEBABE, 0x12345678};
  NSData *data = [NSData dataWithBytes:values length:sizeof(values)];

  uint32_t firstValue = 0;
  NSData *remaining = [FBInstrumentsClient advanceData:data buffer:&firstValue length:sizeof(uint32_t)];

  XCTAssertEqual(firstValue, (uint32_t)0xDEADBEEF, @"First value should be read correctly");
  XCTAssertEqual(remaining.length, (NSUInteger)(sizeof(values) - sizeof(uint32_t)), @"Remaining data should be shorter");

  uint32_t secondValue = 0;
  NSData *remaining2 = [FBInstrumentsClient advanceData:remaining buffer:&secondValue length:sizeof(uint32_t)];
  XCTAssertEqual(secondValue, (uint32_t)0xCAFEBABE);
  XCTAssertEqual(remaining2.length, (NSUInteger)sizeof(uint32_t));
}

- (void)testAdvanceData_WithDataOut_ExtractsSubdataAndAdvances
{
  uint8_t bytes[] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08};
  NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];

  NSData *extracted = nil;
  NSData *remaining = [FBInstrumentsClient advanceData:data dataOut:&extracted length:3];

  XCTAssertNotNil(extracted);
  XCTAssertEqual(extracted.length, (NSUInteger)3);
  uint8_t expectedExtracted[] = {0x01, 0x02, 0x03};
  XCTAssertEqualObjects(extracted, [NSData dataWithBytes:expectedExtracted length:3]);
  XCTAssertEqual(remaining.length, (NSUInteger)5, @"Remaining should have 5 bytes left");
}

- (void)testAdvanceData_WithNilDataOut_StillAdvances
{
  uint8_t bytes[] = {0x01, 0x02, 0x03, 0x04, 0x05};
  NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];

  NSData *remaining = [FBInstrumentsClient advanceData:data dataOut:nil length:2];

  XCTAssertEqual(remaining.length, (NSUInteger)3, @"Should advance past 2 bytes even with nil dataOut");
}

@end
