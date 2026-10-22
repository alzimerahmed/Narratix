//
//  WebDAVPropfindParser.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import Foundation

/// Parses a WebDAV `multistatus` body (PROPFIND Depth: 1) into `WebDAVEntry`s
/// with `XMLParser` — no dependencies, no namespace assumption: servers answer
/// with `d:`, `D:`, or empty prefixes, so element names are compared on their
/// local part only.
///
/// An entry's resource URL resolves its `href` against the directory URL the
/// request went to — servers return absolute paths (`/remote.php/dav/...`),
/// occasionally full URLs, and in odd cases relative hrefs.
final class WebDAVPropfindParser: NSObject, XMLParserDelegate {
  /// The directory the PROPFIND targeted; the listing's own entry is skipped
  private let baseURL: URL
  private(set) var entries: [WebDAVEntry] = []

  /// State while inside a `response` element
  private var currentHref = ""
  private var currentDisplayName: String?
  private var currentIsCollection = false
  private var currentContentLength: Int64?
  /// Inside `resourcetype` — a `collection` child element marks a directory
  private var insideResourcetype = false
  /// Text accumulator for the element being read
  private var text = ""

  init(baseURL: URL) {
    self.baseURL = baseURL
  }

  func parse(_ data: Data) -> [WebDAVEntry] {
    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.shouldProcessNamespaces = false
    parser.parse()
    return entries
  }

  /// The local element name — "d:href", "D:resourcetype", "href" all normalize
  private func localName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    text = ""
    switch localName(elementName) {
    case "response":
      currentHref = ""
      currentDisplayName = nil
      currentIsCollection = false
      currentContentLength = nil
    case "resourcetype":
      insideResourcetype = true
    case "collection" where insideResourcetype:
      currentIsCollection = true
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch localName(elementName) {
    case "href":
      /// A response can carry several hrefs (one per propstat on some
      /// servers); the first is the resource's
      if currentHref.isEmpty { currentHref = trimmed }
    case "displayname":
      currentDisplayName = trimmed.isEmpty ? nil : trimmed
    case "resourcetype":
      insideResourcetype = false
    case "getcontentlength":
      currentContentLength = Int64(trimmed)
    case "response":
      finishResponse()
    default:
      break
    }
    text = ""
  }

  private func finishResponse() {
    guard !currentHref.isEmpty,
      let url = URL(string: currentHref, relativeTo: baseURL)?.absoluteURL
    else { return }

    /// The directory itself shows up in its own Depth:1 listing — drop it
    let basePath = baseURL.standardized.path
    let entryPath = url.standardized.path
    guard entryPath != basePath,
      entryPath + "/" != basePath,
      entryPath != basePath + "/"
    else { return }

    let name = currentDisplayName
      ?? url.lastPathComponent.removingPercentEncoding
      ?? url.lastPathComponent

    entries.append(
      WebDAVEntry(
        url: url,
        name: name,
        isCollection: currentIsCollection,
        contentLength: currentContentLength
      )
    )
  }
}
