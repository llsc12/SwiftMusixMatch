// i wish tr1fecta a sincere fuck you
// this is a joke musixmatch is cool

import SwiftSoup
import Foundation

/// MusixMatch sucks, they have paid api.
public struct MusixMatchAPI {
    
    public static let `default` = Self(session: URLSession.shared)
    let session: URLSession
    
    
    struct Builders {
        static let baseURL = URL(string: "https://www.musixmatch.com")!
        static func search(_ q: String) throws -> URL {
            var search = baseURL.appendingPathComponent("search")
            search.appendPathComponent(q)
            return search
        }
    }
    
    public init(session: URLSession = URLSession.shared) {
        self.session = session
    }
    
    public func getSongs(for q: String) async throws -> MMSearchResults {
        let url = try Builders.search(q)
        var req = URLRequest(url: url)
        // they block you without a useragent or with generic ones
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: req)
        guard let htmlStr = String(data: data, encoding: .utf8) else { throw MMParseError.htmlToStringFailed }
        let html = try SwiftSoup.parse(htmlStr, url.absoluteString)
        
        // Parsing time, get body
        guard let body = html.body() else { throw MMParseError.couldNotGetBody }
        
        // First, get results box, then get results
        guard
            let resultsBox = try? body.select(".tracks.list").last(),
            let results = try? resultsBox.select(".track-card")
        else { throw MMParseError.couldNotExtractResults }
        
        let validResults = results.filter { $0.hasClass("has-add-lyrics") == false }
        
        let parsedResults: MMSearchResults = validResults.compactMap { element in
            guard
                let titleElement = try? element.select(".title"),
                let artistElement = try? element.select(".artist"),
                let title = try? titleElement.text(),
                let artist = try? artistElement.text(),
                let href = try? titleElement.attr("href"),
                let url = URL(string: href, relativeTo: Builders.baseURL)?.absoluteURL
            else { return nil }
            
            let obj = MMSearchResultItem(title: title, artist: artist, url: url)
            return obj
        }
        
        return parsedResults
    }
    
    
    enum MMParseError: Error {
        case htmlToStringFailed
        case couldNotGetBody
        case couldNotExtractResults
        case couldNotExtractLyrics
    }
}

public typealias MMSearchResults = [MMSearchResultItem]

public struct MMSearchResultItem {
    
    public let title: String
    public let artist: String
    
    private let url: URL
        
    internal init(title: String, artist: String, url: URL) {
        self.title = title
        self.artist = artist
        self.url = url
    }
    
    func getLyrics(session: URLSession = MusixMatchAPI.default.session) async throws -> String {
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await session.data(for: req)
        guard let htmlStr = String(data: data, encoding: .utf8) else { throw MusixMatchAPI.MMParseError.htmlToStringFailed }
        let html = try SwiftSoup.parse(htmlStr, url.absoluteString)
        
        guard let body = html.body() else { throw MusixMatchAPI.MMParseError.couldNotGetBody }
        
        guard
            let lyricElements = try? body.select(".mxm-lyrics__content")
        else { throw MusixMatchAPI.MMParseError.couldNotExtractLyrics }

        
        var lyrics = ""
        lyricElements.forEach { elm in
            guard let toAdd = try? elm.children().select("span").text() else { return }
            lyrics += toAdd
            lyrics += "\n"
        }
        
        return lyrics
    }
}

extension MMSearchResultItem: Identifiable {
    public var id: String { self.url.absoluteString }
}
extension MMSearchResultItem: Comparable {
    public static func < (lhs: MMSearchResultItem, rhs: MMSearchResultItem) -> Bool {
        lhs.id == rhs.id
    }
}
