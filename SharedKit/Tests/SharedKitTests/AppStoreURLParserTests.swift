import Foundation
import Testing
@testable import SharedKit

@Suite struct AppStoreURLParserTests {
    @Test func parsesAllSupportedStorefronts() throws {
        let cases: [(String, String, String)] = [
            ("https://apps.apple.com/us/app/example/id123456789", "us", "123456789"),
            ("https://apps.apple.com/hk/app/example/id123456789", "hk", "123456789"),
            ("https://apps.apple.com/jp/app/example/id123456789", "jp", "123456789"),
            ("https://apps.apple.com/cn/app/example/id123456789", "cn", "123456789")
        ]
        for (input, country, trackId) in cases {
            let parsed = try #require(try? AppStoreURLParser.parse(input).get())
            #expect(parsed.countryCode == country)
            #expect(parsed.trackId == trackId)
            #expect(parsed.normalizedURL == "https://apps.apple.com/\(country)/app/id\(trackId)")
        }
    }

    @Test func handlesQueryParametersTrailingSlashAndCase() throws {
        let withQuery = try #require(try? AppStoreURLParser.parse("https://apps.apple.com/us/app/Example-App/id123456789?mt=12&uo=4").get())
        #expect(withQuery.trackId == "123456789")
        #expect(withQuery.countryCode == "us")

        let trailing = try #require(try? AppStoreURLParser.parse("https://apps.apple.com/JP/app/example/id123456789/").get())
        #expect(trailing.countryCode == "jp")

        let uppercase = try #require(try? AppStoreURLParser.parse("https://Apps.Apple.Com/Hk/app/example/ID123456789").get())
        #expect(uppercase.countryCode == "hk")
        #expect(uppercase.trackId == "123456789")
    }

    @Test func acceptsSluglessAndItunesLinks() throws {
        let slugless = try #require(try? AppStoreURLParser.parse("https://apps.apple.com/us/app/id123456789").get())
        #expect(slugless.trackId == "123456789")

        let itunes = try #require(try? AppStoreURLParser.parse("https://itunes.apple.com/cn/app/weekly/id123456789").get())
        #expect(itunes.countryCode == "cn")
    }

    @Test func rejectsMissingTrackId() {
        #expect(AppStoreURLParser.parse("https://apps.apple.com/us/app/example").failure == .missingTrackId)
    }

    @Test func rejectsMalformedTrackId() {
        #expect(AppStoreURLParser.parse("https://apps.apple.com/us/app/example/id12").failure == .invalidTrackId("id12"))
        #expect(AppStoreURLParser.parse("https://apps.apple.com/us/app/example/idabc").failure == .invalidTrackId("idabc"))
    }

    @Test func rejectsUnsupportedHost() {
        #expect(AppStoreURLParser.parse("https://appstore.example.com/us/app/example/id123456789").failure == .unsupportedHost("appstore.example.com"))
        #expect(AppStoreURLParser.parse("https://example.com/id123456789").failure == .unsupportedHost("example.com"))
    }

    @Test func rejectsUnsupportedAndMissingCountry() {
        #expect(AppStoreURLParser.parse("https://apps.apple.com/de/app/example/id123456789").failure == .unsupportedCountry("de"))
        #expect(AppStoreURLParser.parse("https://apps.apple.com/app/id123456789").failure == .missingCountry)
    }

    @Test func rejectsGarbage() {
        #expect(AppStoreURLParser.parse("").failure == .notAURL)
        #expect(AppStoreURLParser.parse("not a url at all").failure == .notAURL)
    }
}

private extension Result where Failure == AppStoreURLParserError {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

