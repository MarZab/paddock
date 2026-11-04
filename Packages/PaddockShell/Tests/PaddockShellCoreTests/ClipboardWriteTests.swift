import Foundation
import Testing
@testable import PaddockShellCore

@Suite("ClipboardWrite")
struct ClipboardWriteTests {
    @Test func keepsText() {
        #expect(ClipboardWrite.text(Data("hello".utf8)) == "hello")
    }

    @Test func refusesEmptyBlankTooLargeOrNonText() {
        #expect(ClipboardWrite.text(Data()) == nil)
        #expect(ClipboardWrite.text(Data(" \n\t".utf8)) == nil)
        #expect(ClipboardWrite.text(Data(repeating: 0x61, count: ClipboardWrite.maxBytes + 1)) == nil)
        #expect(ClipboardWrite.text(Data([0xFF, 0xFE, 0xFD])) == nil)
    }
}
