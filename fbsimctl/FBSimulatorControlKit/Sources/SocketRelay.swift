/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

let DefaultReadLength = 1024
let DefaultWriteCharacters = 512

func acceptCallback(socket: CFSocket!, callback: CFSocketCallBackType, address: NSData!, data: UnsafePointer<Void>, info: UnsafeMutablePointer<Void>) -> Void {
  if callback != CFSocketCallBackType.AcceptCallBack {
    return
  }
  let socketRelay = Unmanaged<SocketRelay>.fromOpaque(COpaquePointer(info)).takeUnretainedValue()
  let localEventReporter = socketRelay.localEventReporter
  localEventReporter.logInfo("Accept \(sockaddr_in.fromData(address))")

  let acceptHandle = UnsafePointer<CFSocketNativeHandle>(data).memory
  let socketHandle = CFSocketGetNative(socket)
  localEventReporter.logInfo("Accept Handle \(acceptHandle) Socket Handle \(socketHandle)")
  assert(acceptHandle != socketHandle, "Accept and Socket FD are the same")

  var readStreamPointer: Unmanaged<CFReadStream>? = nil
  var writeStreamPointer: Unmanaged<CFWriteStream>? = nil

  CFStreamCreatePairWithSocket(
    kCFAllocatorDefault,
    acceptHandle,
    &readStreamPointer,
    &writeStreamPointer
  )

  let readStream = readStreamPointer?.takeUnretainedValue()
  let writeStream = writeStreamPointer?.takeUnretainedValue()

  socketRelay.registerConnection(readStream!, outputStream: writeStream!)
}

extension sockaddr_in6 {
  static func fromData(data: NSData) -> sockaddr_in6 {
    var addr = sockaddr_in6()
    data.getBytes(&addr, length: strideof(sockaddr_in6))
    return addr
  }

  public var description: String {
    return "Port \(self.sin6_port.littleEndian)"
  }
}

extension sockaddr_in {
  static func fromData(data: NSData) -> sockaddr_in {
    var addr = sockaddr_in()
    data.getBytes(&addr, length: strideof(sockaddr_in))
    return addr
  }

  public var description: String {
    return "Port \(self.sin_port)"
  }
}

extension NSStreamStatus {
  public var description: String {
    switch (self) {
    case NotOpen: return "None"
    case Opening: return "Opening"
    case Open: return "Open"
    case Reading: return "Reading"
    case Writing: return "Writing"
    case AtEnd: return "AtEnd"
    case Closed: return "Closed"
    case Error: return "Error"
    }
  }
}

extension NSStreamEvent {
  public var description: String {
    switch (self.rawValue) {
    case NSStreamEvent.None.rawValue: return "None"
    case NSStreamEvent.OpenCompleted.rawValue: return "OpenCompleted"
    case NSStreamEvent.HasBytesAvailable.rawValue: return "HasBytesAvailable"
    case NSStreamEvent.HasSpaceAvailable.rawValue: return "HasSpaceAvailable"
    case NSStreamEvent.ErrorOccurred.rawValue: return "ErrorOccured"
    case NSStreamEvent.EndEncountered.rawValue: return "EndEncountered"
    default: return "Unknown"
    }
  }
}

protocol SocketConnectionDelegate {
  func connectionClosed(socketConnection: SocketConnection)
}

internal class InputDelegate : NSObject, NSStreamDelegate {
  let commandBuffer: CommandBuffer
  let localEventReporter: EventReporter

  init(commandBuffer: CommandBuffer, localEventReporter: EventReporter) {
    self.commandBuffer = commandBuffer
    self.localEventReporter = localEventReporter
  }

  @objc func stream(stream: NSStream, handleEvent eventCode: NSStreamEvent) {
    guard let stream = stream as? NSInputStream else {
      return
    }

    self.localEventReporter.logInfo("Input Event \(eventCode.description)")
    switch (eventCode.rawValue) {
    case NSStreamEvent.HasBytesAvailable.rawValue:
      let buffer = UnsafeMutablePointer<UInt8>.alloc(DefaultReadLength)
      let count = stream.read(buffer, maxLength: DefaultReadLength)
      let data = NSData(bytesNoCopy: buffer, length: count)
      buffer.destroy()

      let commandBuffer = self.commandBuffer
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)) {
        commandBuffer.append(data)
      }
    default:
      return
    }
  }
}

internal class OutputDelegate : NSObject, NSStreamDelegate, Writer {
  var buffer: String = ""
  let stream: NSOutputStream
  let localEventReporter: EventReporter

  init (stream: NSOutputStream, localEventReporter: EventReporter) {
    self.stream = stream
    self.localEventReporter = localEventReporter
  }

  @objc func stream(stream: NSStream, handleEvent eventCode: NSStreamEvent) {
    assert(stream == self.stream, "Handled delegate from unexpected stream")

    self.localEventReporter.logInfo("CommandResult Event \(eventCode.description)")
    switch (eventCode.rawValue) {
    case NSStreamEvent.HasSpaceAvailable.rawValue:
      self.flushAvailable()
    default:
      return
    }
  }

  func write(string: String) {
    buffer.appendContentsOf(string)
    self.flushAvailable()
  }

  func flushAvailable() {
    while (buffer.characters.count > 0 && self.stream.hasSpaceAvailable) {
      // TODO: Buffer appropriately
      let range = buffer.characters.indices
      let slice = buffer.substringWithRange(range)
      self.buffer = ""

      let data = slice.dataUsingEncoding(NSUTF8StringEncoding)!
      let cData = UnsafeMutablePointer<UInt8>.alloc(data.length)
      data.getBytes(cData, length: data.length)
      stream.write(cData, maxLength: data.length)
      cData.destroy()
    }
  }
}


class SocketConnection {
  private let readStream: NSInputStream
  private let readStreamDelegate: InputDelegate

  private let writeStream: NSOutputStream
  private let writeStreamDelegate: OutputDelegate

  init(readStream: NSInputStream, readStreamDelegate: InputDelegate, writeStream: NSOutputStream, writeStreamDelegate: OutputDelegate) {
    self.readStream = readStream
    self.readStreamDelegate = readStreamDelegate
    self.writeStream = writeStream
    self.writeStreamDelegate = writeStreamDelegate
  }

  convenience init(readStream: NSInputStream, writeStream: NSOutputStream, delegate: SocketConnectionDelegate, commandBuffer: CommandBuffer, outputOptions: OutputOptions, localEventReporter: EventReporter) {
    let write = OutputDelegate(stream: writeStream, localEventReporter: localEventReporter)
    let read = InputDelegate(
      commandBuffer: LineBuffer(performer: commandBuffer.performer, reporter: outputOptions.createReporter(write)),
      localEventReporter: localEventReporter
    )
    self.init(readStream: readStream, readStreamDelegate: read, writeStream: writeStream, writeStreamDelegate: write)
  }

  func start() {
    assert(self.readStream.streamStatus == NSStreamStatus.NotOpen, "Expected an unopened Read Stream")
    assert(self.writeStream.streamStatus == NSStreamStatus.NotOpen, "Expected an unopened Write Stream")

    self.readStream.delegate = self.readStreamDelegate
    self.readStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
    self.readStream.open()

    self.writeStream.delegate = self.writeStreamDelegate
    self.writeStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
    self.writeStream.open()
  }

  func stop() {
    self.readStream.close()
    self.writeStream.close()
  }
}

class SocketRelay : Relay, SocketConnectionDelegate {
  struct Options {
    let portNumber: in_port_t
    let bindIPv4: Bool
    let bindIPv6: Bool
    let outputOptions: OutputOptions

    func portNumberNetworkByteOrder() -> in_port_t {
      return UInt16(self.portNumber).bigEndian
    }
  }

  let socketOptions: SocketRelay.Options
  let commandBuffer: CommandBuffer
  let localEventReporter: EventReporter
  var registeredConnections: [SocketConnection] = []

  init(portNumber: in_port_t, commandBuffer: CommandBuffer, localEventReporter: EventReporter, socketOutput: OutputOptions) {
    self.socketOptions = SocketRelay.Options(portNumber: portNumber, bindIPv4: false, bindIPv6: true, outputOptions: socketOutput)
    self.commandBuffer = commandBuffer
    self.localEventReporter = localEventReporter
  }

  func start() {
    self.createSocketsAndRunInRunLoop()
  }

  func stop() {

  }

  private func socketContext() -> CFSocketContext {
    return CFSocketContext(
      version: 0,
      info: UnsafeMutablePointer(Unmanaged.passUnretained(self).toOpaque()),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
  }

  private func setSocketOptions(socket: CFSocket) {
    let socketDescriptor = CFSocketGetNative(socket)
    var yes: Int32 = 1
    let result = setsockopt(socketDescriptor, Constants.sol_socket(), Constants.so_reuseaddr(), &yes, UInt32(strideof(Int32)))
    assert(result != -1, "Expected to be able to setsockopt")
  }

  private func createSocket4() -> CFSocket {
    var context = socketContext()
    let sock = CFSocketCreate(
      kCFAllocatorDefault,
      PF_INET,
      SOCK_STREAM,
      IPPROTO_TCP,
      CFSocketCallBackType.AcceptCallBack.rawValue,
      acceptCallback,
      &context
    )
    setSocketOptions(sock)

    var addr = sockaddr_in(
      sin_len: UInt8(strideof(sockaddr_in)),
      sin_family: UInt8(AF_INET),
      sin_port: self.socketOptions.portNumberNetworkByteOrder(),
      sin_addr: in_addr(s_addr: UInt32(0).bigEndian),
      sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
    )

    let data: CFDataRef = NSData(bytes: &addr, length: strideof(sockaddr_in))
    let error = CFSocketSetAddress(sock, data)
    assert(error == CFSocketError.Success, "Could not bind ipv4")

    return sock
  }

  private func createSocket6() -> CFSocket {
    var context = socketContext()
    let sock = CFSocketCreate(
      kCFAllocatorDefault,
      PF_INET6,
      SOCK_STREAM,
      IPPROTO_TCP,
      CFSocketCallBackType.AcceptCallBack.rawValue,
      acceptCallback,
      &context
    )
    setSocketOptions(sock)

    var addr = sockaddr_in6(
      sin6_len: UInt8(strideof(sockaddr_in6)),
      sin6_family: UInt8(AF_INET6),
      sin6_port: self.socketOptions.portNumberNetworkByteOrder(),
      sin6_flowinfo: 0,
      sin6_addr: in6addr_any,
      sin6_scope_id: 0
    )

    let data: CFDataRef = NSData(bytes: &addr, length: strideof(sockaddr_in6))
    let error = CFSocketSetAddress(sock, data)
    assert(error == CFSocketError.Success, "Could not bind ipv6")

    return sock
  }

  func createSocketsAndRunInRunLoop() {
    var sockets: [CFSocket] = []

    if (self.socketOptions.bindIPv4) {
      sockets.append(createSocket4())
    }
    if (self.socketOptions.bindIPv6) {
      sockets.append(createSocket6())
    }

    for socket in sockets {
      let source = CFSocketCreateRunLoopSource(
        kCFAllocatorDefault,
        socket,
        0
      )
      CFRunLoopAddSource(
        CFRunLoopGetCurrent(),
        source,
        kCFRunLoopDefaultMode
      )

      let native = CFSocketGetNative(socket)
      self.localEventReporter.logDebug("Got a Native Socket of \(native)")
      assert(native != 0, "Couldn't get native socket")
    }
  }

  func registerConnection(inputStream: NSInputStream, outputStream: NSOutputStream) {
    let connection = SocketConnection(
      readStream: inputStream,
      writeStream: outputStream,
      delegate: self,
      commandBuffer: self.commandBuffer,
      outputOptions: self.socketOptions.outputOptions,
      localEventReporter: self.localEventReporter
    )

    registeredConnections.append(connection)
    connection.start()
  }

  func connectionClosed(socketConnection: SocketConnection) {

  }
}
