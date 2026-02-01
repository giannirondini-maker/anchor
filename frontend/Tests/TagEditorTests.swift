/**
 * Tag Editor View Tests
 *
 * Unit tests for tag editor components and utilities
 */

import XCTest
import SwiftUI
@testable import Anchor

final class TagEditorTests: XCTestCase {
    
    // MARK: - Color Hex Extension Tests
    
    func testColorFromValidHexWithHash() {
        let color = Color(hex: "#FF5733")
        XCTAssertNotNil(color)
    }
    
    func testColorFromValidHexWithoutHash() {
        let color = Color(hex: "FF5733")
        XCTAssertNotNil(color)
    }
    
    func testColorFromInvalidHex() {
        let color = Color(hex: "invalid")
        XCTAssertNil(color)
    }
    
    func testColorFromEmptyString() {
        let color = Color(hex: "")
        XCTAssertNil(color)
    }
    
    func testColorFromShortHex() {
        // Short hex (3 characters) is not supported by our implementation
        let color = Color(hex: "F00")
        XCTAssertNil(color)
    }
    
    func testColorFromHexWithWhitespace() {
        let color = Color(hex: "  #FF5733  ")
        XCTAssertNotNil(color)
    }
    
    func testColorFromLowercaseHex() {
        let color = Color(hex: "#ff5733")
        XCTAssertNotNil(color)
    }
    
    func testColorFromMixedCaseHex() {
        let color = Color(hex: "#Ff5733")
        XCTAssertNotNil(color)
    }
    
    // MARK: - Tag Input Parsing Tests
    
    func testParseCommaSeparatedTags() {
        let input = "tag1, tag2, tag3"
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        XCTAssertEqual(tags.count, 3)
        XCTAssertEqual(tags[0], "tag1")
        XCTAssertEqual(tags[1], "tag2")
        XCTAssertEqual(tags[2], "tag3")
    }
    
    func testParseCommaSeparatedTagsWithExtraSpaces() {
        let input = "  tag1  ,  tag2  ,  tag3  "
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        XCTAssertEqual(tags.count, 3)
        XCTAssertEqual(tags[0], "tag1")
        XCTAssertEqual(tags[1], "tag2")
        XCTAssertEqual(tags[2], "tag3")
    }
    
    func testParseCommaSeparatedTagsWithEmptySegments() {
        let input = "tag1,,tag2,  ,tag3"
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        XCTAssertEqual(tags.count, 3)
    }
    
    func testParseSingleTag() {
        let input = "SingleTag"
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0], "SingleTag")
    }
    
    func testParseEmptyInput() {
        let input = ""
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        XCTAssertTrue(tags.isEmpty)
    }
    
    func testParseWhitespaceOnlyInput() {
        let input = "   ,  ,   "
        let tags = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        XCTAssertTrue(tags.isEmpty)
    }
}
