import XCTest
@testable import SwiftMusixMatch
import SwiftSoup

final class SwiftMusixMatchTests: XCTestCase {
    func testResults() async throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        
        let results = try await MusixMatchAPI.default.getSongs(for: "crystal dolphin")
        for result in results {
            print(result.title)
        }
        XCTAssert(results.count == 10)
    }
    
    func testLyrics() async throws {
        let results = try await MusixMatchAPI.default.getSongs(for: "crystal dolphin")
        
        let song = results.first!
        
        let lyrics = try await song.getLyrics()
        let lines = lyrics.components(separatedBy: "\n")
        XCTAssert(lines.count > 5)
    }
    
    func testTranslations() async throws {
        let results = try await MusixMatchAPI.default.getSongs(for: "crystal dolphin")
        
        let song = results.first!
        
        let translations = try await song.getTranslations()
        
        translations.forEach { translation in
            print("[Translations Test] \(translation.lang) (\((translation.percentTranslated*100).rounded().description)% translated)")
        }
    }
}
