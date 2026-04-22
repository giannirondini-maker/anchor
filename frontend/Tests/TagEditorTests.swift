/**
 * Tag Editor View Tests
 *
 * Unit tests for tag editor components and utilities
 */

import Foundation
import Testing
import SwiftUI
@testable import Anchor

struct TagEditorTests {

    // MARK: - Color Hex Extension Tests

    @Test func testColorFromValidHexWithHash() {
        let color = Color(hex: "#FF5733")
        #expect(color != nil)
    }

    @Test func testColorFromValidHexWithoutHash() {
        let color = Color(hex: "FF5733")
        #expect(color != nil)
    }

    @Test func testColorFromInvalidHex() {
        let color = Color(hex: "invalid")
        #expect(color == nil)
    }

    @Test func testColorFromEmptyString() {
        let color = Color(hex: "")
        #expect(color == nil)
    }

    @Test func testColorFromShortHex() {
        // Short hex (3 characters) is not supported by our implementation
        let color = Color(hex: "F00")
        #expect(color == nil)
    }

    @Test func testColorFromHexWithWhitespace() {
        let color = Color(hex: "  #FF5733  ")
        #expect(color != nil)
    }

    @Test func testColorFromLowercaseHex() {
        let color = Color(hex: "#ff5733")
        #expect(color != nil)
    }

    @Test func testColorFromMixedCaseHex() {
        let color = Color(hex: "#Ff5733")
        #expect(color != nil)
    }
    
    // MARK: - Tag Input Parsing Tests

    @Test func testParseCommaSeparatedTags() {
        let input = "tag1, tag2, tag3"
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        #expect(tags.count == 3)
        #expect(tags[0] == "tag1")
        #expect(tags[1] == "tag2")
        #expect(tags[2] == "tag3")
    }

    @Test func testParseCommaSeparatedTagsWithExtraSpaces() {
        let input = "  tag1  ,  tag2  ,  tag3  "
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        #expect(tags.count == 3)
        #expect(tags[0] == "tag1")
        #expect(tags[1] == "tag2")
        #expect(tags[2] == "tag3")
    }

    @Test func testParseCommaSeparatedTagsWithEmptySegments() {
        let input = "tag1,,tag2,  ,tag3"
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        #expect(tags.count == 3)
    }

    @Test func testParseSingleTag() {
        let input = "SingleTag"
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        #expect(tags.count == 1)
        #expect(tags[0] == "SingleTag")
    }

    @Test func testParseEmptyInput() {
        let input = ""
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        #expect(tags.isEmpty)
    }

    @Test func testParseWhitespaceOnlyInput() {
        let input = "   ,  ,   "
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        #expect(tags.isEmpty)
    }
}
