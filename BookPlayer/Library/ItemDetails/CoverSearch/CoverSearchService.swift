//
//  CoverSearchService.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation

/// One online cover candidate from the iTunes Search API
struct CoverSearchResult: Identifiable, Hashable, Sendable {
  /// The artwork URL is unique per result
  var id: String { imageURL.absoluteString }
  /// ~100px, for the results grid
  let thumbnailURL: URL
  /// ~600px, the image that gets applied
  let imageURL: URL
  let title: String
  let author: String
}

/// Online cover lookup through the iTunes Search API — no API key, no account,
/// no credentials in any request, so it's safe for a GPL build. Audiobooks are
/// searched first, books as the fallback (iTunes carries the same catalog the
/// old Audible artwork lookup drew from).
///
/// `session` is injectable so tests can stub the network with a URLProtocol.
final class CoverSearchService: BPLogger, @unchecked Sendable {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func search(query: String) async throws -> [CoverSearchResult] {
    let audiobooks = try await search(query: query, media: "audiobook")
    if !audiobooks.isEmpty { return audiobooks }
    return try await search(query: query, media: "ebook")
  }

  /// Fetch the full-resolution image for a chosen result
  func imageData(for result: CoverSearchResult) async throws -> Data {
    let (data, response) = try await session.data(from: result.imageURL)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw BookPlayerError.networkError("Cover download failed")
    }
    return data
  }

  private func search(query: String, media: String) async throws -> [CoverSearchResult] {
    var components = URLComponents(string: "https://itunes.apple.com/search")
    components?.queryItems = [
      URLQueryItem(name: "term", value: query),
      URLQueryItem(name: "media", value: media),
      URLQueryItem(name: "limit", value: "25"),
    ]
    guard let url = components?.url else {
      throw BookPlayerError.runtimeError("Invalid cover search query")
    }

    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw BookPlayerError.networkError("Cover search failed")
    }

    return Self.parse(data)
  }

  /// `artworkUrl100` is the 100px thumbnail; swapping the size segment asks the
  /// CDN for 600px — a documented convention of the search API's artwork URLs
  static func parse(_ data: Data) -> [CoverSearchResult] {
    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let results = json["results"] as? [[String: Any]]
    else { return [] }

    return results.compactMap { result -> CoverSearchResult? in
      guard
        let artwork = result["artworkUrl100"] as? String,
        let thumbnailURL = URL(string: artwork),
        let imageURL = URL(
          string: artwork.replacingOccurrences(of: "100x100", with: "600x600")
        )
      else { return nil }

      return CoverSearchResult(
        thumbnailURL: thumbnailURL,
        imageURL: imageURL,
        title: result["collectionName"] as? String
          ?? result["trackName"] as? String
          ?? "",
        author: result["artistName"] as? String ?? ""
      )
    }
  }
}
