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

func acceptCallback(socket: CFSocket?, callback: CFSocketCallBackType, address: CFData?, data: UnsafeRawPointer?, info: UnsafeMutableRawPointer?) -> Void {
  if callback != CFSocketCallBackType.acceptCallBack {
    return
  }
  guard let data = data, let info = info else {
    return
  }

  let socketRelay = Unmanaged<SocketRelay>.fromOpaque(info).takeUnretainedValue()
  let localEventReporter = socketRelay.localEventReporter

  let acceptHandle = data.load(as: CFSocketNativeHandle.self)
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
  static func fromData(_ data: Data) -> sockaddr_in6 {
    var addr = sockaddr_in6()
    (data as NSData).getBytes(&addr, length: MemoryLayout<sockaddr_in6>.stride)
    return addr
  }

  public var description: String {
    return "Port \(self.sin6_port.littleEndian)"
  }
}

extension sockaddr_in {
  static func fromData(_ data: Data) -> sockaddr_in {
    var addr = sockaddr_in()
    (data as NSData).getBytes(&addr, length: MemoryLayout<sockaddr_in>.stride)
    return addr
  }

  public var description: String {
    return "Port \(self.sin_port)"
  }
}

extension Stream.Status {
  public var description: String {
    switch (self) {
    case .notOpen: return "None"
    case .opening: return "Opening"
    case .open: return "Open"
    case .reading: return "Reading"
    case .writing: return "Writing"
    case .atEnd: return "AtEnd"
    case .closed: return "Closed"
    case .error: return "Error"
    }
  }
}

extension Stream.Event {
  public var description: String {
    switch (self.rawValue) {
    case Stream.Event().rawValue: return "None"
    case Stream.Event.openCompleted.rawValue: return "OpenCompleted"
    case Stream.Event.hasBytesAvailable.rawValue: return "HasBytesAvailable"
    case Stream.Event.hasSpaceAvailable.rawValue: return "HasSpaceAvailable"
    case Stream.Event.errorOccurred.rawValue: return "ErrorOccured"
    case Stream.Event.endEncountered.rawValue: return "EndEncountered"
    default: return "Unknown"
    }
  }
}

protocol SocketConnectionDelegate {
  func connectionClosed(_ socketConnection: SocketConnection)
}

internal class InputDelegate : NSObject, StreamDelegate {
  let commandBuffer: CommandBuffer
  let localEventReporter: EventReporter

  init(commandBuffer: CommandBuffer, localEventReporter: EventReporter) {
    self.commandBuffer = commandBuffer
    self.localEventReporter = localEventReporter
  }

  @objc func stream(_ stream: Stream, handle eventCode: Stream.Event) {
    guard let stream = stream as? InputStream else {
      return
    }

    self.localEventReporter.logInfo("Input Event \(eventCode.description)")
    switch (eventCode.rawValue) {
    case Stream.Event.hasBytesAvailable.rawValue:
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: DefaultReadLength)
      let count = stream.read(buffer, maxLength: DefaultReadLength)
      let data = Data(bytesNoCopy: UnsafeMutablePointer<UInt8>(buffer), count: count, deallocator: .free)
      buffer.deinitialize()

      let commandBuffer = self.commandBuffer
      DispatchQueue.global(qos: DispatchQoS.userInitiated.qosClass).async {
        let _ = commandBuffer.append(data)
      }
    default:
      return
    }
  }
}

internal class OutputDelegate : NSObject, StreamDelegate, Writer {
  var buffer: String = ""
  let stream: OutputStream
  let localEventReporter: EventReporter

  init (stream: OutputStream, localEventReporter: EventReporter) {
    self.stream = stream
    self.localEventReporter = localEventReporter
  }

  @objc func stream(_ stream: Stream, handle eventCode: Stream.Event) {
    assert(stream == self.stream, "Handled delegate from unexpected stream")

    self.localEventReporter.logInfo("CommandResult Event \(eventCode.description)")
    switch (eventCode.rawValue) {
    case Stream.Event.hasSpaceAvailable.rawValue:
      self.flushAvailable()
    default:
      return
    }
  }

  func write(_ string: String) {
    buffer.append(string)
    self.flushAvailable()
  }

  func flushAvailable() {
    while (buffer.characters.count > 0 && self.stream.hasSpaceAvailable) {
      // TODO: Buffer appropriately
      let slice = buffer
      self.buffer = ""

      let data = slice.data(using: String.Encoding.utf8)!
      let cData = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
      (data as NSData).getBytes(cData, length: data.count)
      stream.write(cData, maxLength: data.count)
      cData.deinitialize()
    }
  }
}


class SocketConnection {
  fileprivate let readStream: InputStream
  fileprivate let readStreamDelegate: InputDelegate

  fileprivate let writeStream: OutputStream
  fileprivate let writeStreamDelegate: OutputDelegate

  init(readStream: InputStream, readStreamDelegate: InputDelegate, writeStream: OutputStream, writeStreamDelegate: OutputDelegate) {
    self.readStream = readStream
    self.readStreamDelegate = readStreamDelegate
    self.writeStream = writeStream
    self.writeStreamDelegate = writeStreamDelegate
  }

  convenience init(readStream: InputStream, writeStream: OutputStream, delegate: SocketConnectionDelegate, commandBuffer: CommandBuffer, outputOptions: OutputOptions, localEventReporter: EventReporter) {
    let write = OutputDelegate(stream: writeStream, localEventReporter: localEventReporter)
    let read = InputDelegate(
      commandBuffer: LineBuffer(performer: commandBuffer.performer, reporter: outputOptions.createReporter(write)),
      localEventReporter: localEventReporter
    )
    self.init(readStream: readStream, readStreamDelegate: read, writeStream: writeStream, writeStreamDelegate: write)
  }

  func start() {
    assert(self.readStream.streamStatus == Stream.Status.notOpen, "Expected an unopened Read Stream")
    assert(self.writeStream.streamStatus == Stream.Status.notOpen, "Expected an unopened Write Stream")

    self.readStream.delegate = self.readStreamDelegate
    self.readStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
    self.readStream.open()

    self.writeStream.delegate = self.writeStreamDelegate
    self.writeStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
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

  fileprivate func socketContext() -> CFSocketContext {
    return CFSocketContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
  }

  fileprivate func setSocketOptions(_ socket: CFSocket) {
    let socketDescriptor = CFSocketGetNative(socket)
    var yes: Int32 = 1
    let result = setsockopt(socketDescriptor, Constants.sol_socket(), Constants.so_reuseaddr(), &yes, UInt32(MemoryLayout<Int32>.stride))
    assert(result != -1, "Expected to be able to setsockopt")
  }

  fileprivate func createSocket4() -> CFSocket {
    var context = socketContext()
    let sock = CFSocketCreate(
      kCFAllocatorDefault,
      PF_INET,
      SOCK_STREAM,
      IPPROTO_TCP,
      CFSocketCallBackType.acceptCallBack.rawValue,
      acceptCallback,
      &context
    )
    setSocketOptions(sock!)

    var addr = sockaddr_in(
      sin_len: UInt8(MemoryLayout<sockaddr_in>.stride),
      sin_family: UInt8(AF_INET),
      sin_port: self.socketOptions.portNumberNetworkByteOrder(),
      sin_addr: in_addr(s_addr: UInt32(0).bigEndian),
      sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
    )

    let data = Data(bytes: &addr, count: MemoryLayout.stride(ofValue: addr))
    let error = CFSocketSetAddress(sock, data as CFData!)
    assert(error == CFSocketError.success, "Could not bind ipv4")

    return sock!
  }

  fileprivate func createSocket6() -> CFSocket {
    var context = socketContext()
    let sock = CFSocketCreate(
      kCFAllocatorDefault,
      PF_INET6,
      SOCK_STREAM,
      IPPROTO_TCP,
      CFSocketCallBackType.acceptCallBack.rawValue,
      acceptCallback,
      &context
    )
    setSocketOptions(sock!)

    var addr = sockaddr_in6(
      sin6_len: UInt8(MemoryLayout<sockaddr_in6>.stride),
      sin6_family: UInt8(AF_INET6),
      sin6_port: self.socketOptions.portNumberNetworkByteOrder(),
      sin6_flowinfo: 0,
      sin6_addr: in6addr_any,
      sin6_scope_id: 0
    )

    let data = Data(bytes: &addr, count: MemoryLayout.stride(ofValue: addr))
    let error = CFSocketSetAddress(sock, data as CFData!)
    assert(error == CFSocketError.success, "Could not bind ipv6")

    return sock!
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
        CFRunLoopMode.defaultMode
      )

      let native = CFSocketGetNative(socket)
      self.localEventReporter.logDebug("Got a Native Socket of \(native)")
      assert(native != 0, "Couldn't get native socket")
    }
  }

  func registerConnection(_ inputStream: InputStream, outputStream: OutputStream) {
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

  func connectionClosed(_ socketConnection: SocketConnection) {

  }
}
