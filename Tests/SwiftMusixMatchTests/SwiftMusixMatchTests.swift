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
    }
    
    func testLyrics() async throws {
        let results = try await MusixMatchAPI.default.getSongs(for: "crystal dolphin")
        
        let song = results.first!
        
        let lyrics = try await song.getLyrics()
        let lines = lyrics.components(separatedBy: "\n")
        print(lines§)
    }
    
    
    func testSwiftSoup() async throws {
        let str = """
<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8" />
    <title>gm</title>
  </head>
  <body>
    <p>
      <span>
      gm
      this is some test

      yoo its another paragraph!
      more text

      this is a new paragraph
      gm is the best
      </span>
    </p>
  </body>
</html>
"""
        let doc = try parse(str)
        let elmnt = try doc.body()?.select("span")
        let gm = try elmnt?.text()
        print(gm)
    }
}
