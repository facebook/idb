/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorVideo
import Testing

private func color(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> SIMD4<UInt8> {
  SIMD4(r, g, b, 255)
}

private func cell(_ top: SIMD4<UInt8>, _ bottom: SIMD4<UInt8>) -> TerminalCell {
  TerminalCell(top: top, bottom: bottom)
}

private func fg(_ c: SIMD4<UInt8>) -> String { "\u{1B}[38;2;\(c.x);\(c.y);\(c.z)m" }
private func bg(_ c: SIMD4<UInt8>) -> String { "\u{1B}[48;2;\(c.x);\(c.y);\(c.z)m" }
private func move(_ row: Int, _ column: Int) -> String { "\u{1B}[\(row);\(column)H" }
private let clear = "\u{1B}[2J"
private let reset = "\u{1B}[0m"

private let red = color(255, 0, 0)
private let green = color(0, 255, 0)
private let blue = color(0, 0, 255)
private let white = color(255, 255, 255)
private let black = color(0, 0, 0)

private func render(_ formatter: inout ANSIFrameFormatter, _ cells: [TerminalCell], columns: Int, rows: Int = 1) -> String {
  String(decoding: formatter.format(cells, grid: TerminalGrid(columns: columns, rows: rows)), as: UTF8.self)
}

@Suite struct ANSIFrameFormatterTests {
  @Test func firstFrameClearsAndWritesEveryCell() {
    var formatter = ANSIFrameFormatter(mode: .half, threshold: 0)
    let output = render(&formatter, [cell(red, green), cell(blue, white)], columns: 2)
    #expect(output == clear + move(1, 1) + fg(red) + bg(green) + "▀" + fg(blue) + bg(white) + "▀" + reset)
  }

  @Test func rowsAreEachAddressed() {
    var formatter = ANSIFrameFormatter(mode: .half, threshold: 0)
    let output = render(&formatter, [cell(red, red), cell(red, red)], columns: 1, rows: 2)
    #expect(output == clear + move(1, 1) + fg(red) + bg(red) + "▀" + move(2, 1) + "▀" + reset)
  }

  @Test func unchangedFrameWritesNothing() {
    var formatter = ANSIFrameFormatter(mode: .half, threshold: 0)
    let cells = [cell(red, green), cell(blue, white)]
    _ = render(&formatter, cells, columns: 2)
    #expect(render(&formatter, cells, columns: 2).isEmpty)
  }

  @Test func changedCellIsAddressedDirectly() {
    var formatter = ANSIFrameFormatter(mode: .half, threshold: 0)
    _ = render(&formatter, [cell(red, green), cell(blue, white)], columns: 2)
    let output = render(&formatter, [cell(red, green), cell(black, white)], columns: 2)
    #expect(output == move(1, 2) + fg(black) + bg(white) + "▀" + reset)
  }

  @Test func adjacentChangesShareOneCursorMove() {
    var formatter = ANSIFrameFormatter(mode: .half, threshold: 0)
    _ = render(&formatter, [cell(red, red), cell(red, red), cell(red, red)], columns: 3)
    let output = render(&formatter, [cell(red, red), cell(blue, blue), cell(green, green)], columns: 3)
    #expect(output == move(1, 2) + fg(blue) + bg(blue) + "▀" + fg(green) + bg(green) + "▀" + reset)
  }

  @Test func subThresholdChangeIsNotWritten() {
    var formatter = ANSIFrameFormatter(mode: .half, threshold: 4)
    _ = render(&formatter, [cell(color(100, 100, 100), black)], columns: 1)
    #expect(render(&formatter, [cell(color(104, 100, 100), black)], columns: 1).isEmpty)
  }

  @Test func driftIsMeasuredAgainstWhatIsOnScreen() {
    var formatter = ANSIFrameFormatter(mode: .half, threshold: 4)
    _ = render(&formatter, [cell(color(100, 100, 100), black)], columns: 1)
    _ = render(&formatter, [cell(color(104, 100, 100), black)], columns: 1)
    let output = render(&formatter, [cell(color(108, 100, 100), black)], columns: 1)
    #expect(output == move(1, 1) + fg(color(108, 100, 100)) + bg(black) + "▀" + reset)
  }

  @Test func gridChangeRedrawsInFull() {
    var formatter = ANSIFrameFormatter(mode: .half, threshold: 0)
    _ = render(&formatter, [cell(red, red)], columns: 1)
    let output = render(&formatter, [cell(red, red), cell(red, red)], columns: 2)
    #expect(output == clear + move(1, 1) + fg(red) + bg(red) + "▀▀" + reset)
  }

  @Test func invalidateRedrawsInFull() {
    var formatter = ANSIFrameFormatter(mode: .half, threshold: 0)
    _ = render(&formatter, [cell(red, red)], columns: 1)
    formatter.invalidate()
    #expect(render(&formatter, [cell(red, red)], columns: 1) == clear + move(1, 1) + fg(red) + bg(red) + "▀" + reset)
  }

  @Test func asciiModeMapsBrightnessOntoRamp() {
    var formatter = ANSIFrameFormatter(mode: .ascii, threshold: 0)
    let output = render(&formatter, [cell(black, black), cell(white, white)], columns: 2)
    #expect(output == clear + move(1, 1) + fg(black) + " " + fg(white) + "@" + reset)
  }
}
