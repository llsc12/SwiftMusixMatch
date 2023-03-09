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
    
    /// Searches MusixMatch for songs.
    /// - Parameter q: Search query.
    /// - Returns: A list of song objects.
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
            
            let obj = MMSongItem(title: title, artist: artist, url: url)
            return obj
        }
        
        return parsedResults
    }
    
    
    enum MMParseError: Error {
        case htmlToStringFailed
        case couldNotGetBody
        case couldNotExtractResults
        case couldNotExtractLyrics
        case couldNotExtractDataPayload
        case jsonReadError
    }
}

public typealias MMSearchResults = [MMSongItem]

/// A song object which lets you see basic metadata and get lyrics.
public struct MMSongItem {
    
    public let title: String
    public let artist: String
    
    private let url: URL
        
    internal init(title: String, artist: String, url: URL) {
        self.title = title
        self.artist = artist
        self.url = url
    }
    
    /// Gets the lyrics of this song
    /// - Parameters:
    ///   - translation: Translation to get lyrics for, leave nil to get original lyrics. Get available translations with getCommonTranslations().
    ///   - session: The URLSession to use, for advanced use.
    /// - Returns: Formatted lyrics string.
    public func getLyrics(_ translation: Translation? = nil, session: URLSession = URLSession.shared) async throws -> String {
        if let translation {
            let body = try await getPageBody(translation.path, session: session)

            guard
                let translatedLyricsContainer = try
                    body
                        .select(".mxm-lyrics.translated")
                        .select(".row")
                        .select(".col-xs-12.col-sm-12.col-md-12.col-ml-12.col-lg-12")
                        .first()
            else {
                throw MusixMatchAPI.MMParseError.couldNotExtractLyrics
            }
            
            var lyrics = ""
            
            let containerRows = translatedLyricsContainer.children()
            
            containerRows.forEach { containerRow in
                if let innerRow = try? containerRow.select(".row>.col-xs-6.col-sm-6.col-md-6.col-ml-6.col-lg-6") {
//                    let original = innerRow.first()
                    let translation = innerRow.last()
                    if let lyric = try? translation?.text() {
                        lyrics += lyric
                        lyrics += "\n"
                    }
                }
            }
            
            return lyrics
                    
        } else {
            let body = try await getPageBody(nil, session: session)
            
            guard
                let lyricElements = try? body.select(".mxm-lyrics__content")
            else { throw MusixMatchAPI.MMParseError.couldNotExtractLyrics }
            
            
            var lyrics = ""
            lyricElements.forEach { elm in
                guard let toAdd = try? elm.children().select("span").text(trimAndNormaliseWhitespace: false) else { return }
                lyrics += toAdd
                lyrics += "\n"
            }
            
            return lyrics
        }
    }
    
    /// Gets all the available translations for this song.
    /// - Parameter session: The URLSession to use, for advanced use.
    /// - Returns: Array of Translations
    public func getTranslations(session: URLSession = URLSession.shared) async throws -> [Translation] {
        let body = try await getPageBody(nil, session: session)
        
        // theres a script tag with a ton of data. we get translations with it.
        let scripts = try body.select("script")
        
        // filter out the right one
        guard let payloadScript = scripts.filter({ element in
            element.description.contains("};var __mxmState = ")
        }).first else { throw MusixMatchAPI.MMParseError.couldNotExtractDataPayload }
        
        let cleanedPayload = payloadScript.description.dropFirst("<script>var __mxmProps = {\"pageProps\":{\"pageName\":\"track\"}};var __mxmState = ".count).dropLast(";</script>".count)
        
        guard let payload = cleanedPayload.data(using: .utf8) else { throw MusixMatchAPI.MMParseError.couldNotExtractDataPayload }
        
        // get the list of translations
        guard
            let json = try JSONSerialization.jsonObject(with: payload) as? Dictionary<String, Any>,
            let lyrics = json["page"] as? [String: Any],
            let track = lyrics["track"] as? [String: Any],
            let translationsJson = track["lyricsTranslationStatus"] as? [[String: Any]]
        else { throw MusixMatchAPI.MMParseError.jsonReadError }
        
        let translationData = try JSONSerialization.data(withJSONObject: translationsJson)
        let translationObjects = try JSONDecoder().decode([translationObj].self, from: translationData)
        
        let optionalObjects: [Translation?] = translationObjects.map { obj in
            let engLocale = Locale(identifier: "en")
            
            let langSiteCodeFiltered = obj.to.filter { char in ("A"..."Z").contains(char.uppercased()) }
            guard let langCode = Locale(identifier: langSiteCodeFiltered).languageCode else { return nil }
            
            let fromLangSiteCodeFiltered = obj.to.filter { char in ("A"..."Z").contains(char.uppercased()) }
            guard let fromLangCode = Locale(identifier: fromLangSiteCodeFiltered).languageCode else { return nil }
            
            guard let langName = engLocale.localizedString(forLanguageCode: langCode) else { return nil }
            guard let fromLangName = engLocale.localizedString(forLanguageCode: fromLangCode) else { return nil }
            
            return Translation(lang: langName, translatedFromLang: fromLangName, percentTranslated: obj.perc, path: "translation/\(langName.lowercased())")
        }
        
        let finalObjects: [Translation] = optionalObjects.compactMap {$0}
        
        return finalObjects
    }
    
    private struct translationObj: Codable {
        let to: String
        let from: String
        let perc: Float
    }
    
    internal func getPageBody(_ pathExt: String? = nil, session: URLSession) async throws -> Element {
        let reqUrl = url.appendingPathComponent(pathExt ?? "")
        var req = URLRequest(url: reqUrl)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await session.data(for: req)
        guard let htmlStr = String(data: data, encoding: .utf8) else { throw MusixMatchAPI.MMParseError.htmlToStringFailed }
        let html = try SwiftSoup.parse(htmlStr, url.absoluteString)
        
        guard let body = html.body() else { throw MusixMatchAPI.MMParseError.couldNotGetBody }
        return body
    }
    
    /// Pass this to the getLyrics() function to get the lyrics in this particular language.
    public struct Translation {
        
        /// This should only be used if you know a translation is available.
        /// - Parameter lang: Language to grab.
        public init(_ lang: String) {
            self.init(lang: lang, translatedFromLang: "", percentTranslated: 1, path: "translation/\(lang)")
        }
        
        internal init(lang: String, translatedFromLang: String, percentTranslated: Float, path: String) {
            self.lang = lang
            self.path = path
            self.percentTranslated = percentTranslated
            self.translatedFromLang = translatedFromLang
        }
        
        public let lang: String
        public let translatedFromLang: String
        public let percentTranslated: Float
        
        internal let path: String
    }
}

extension MMSongItem: Identifiable {
    public var id: String { self.url.absoluteString }
}
extension MMSongItem: Equatable {
    public static func == (lhs: MMSongItem, rhs: MMSongItem) -> Bool {
        lhs.id == rhs.id
    }
}
