//
//  WebDAVPropfindParserTests.swift
//  BookPlayerTests
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import XCTest

@testable import BookPlayer

/// The multistatus parser normalizes namespace prefixes, resolves hrefs against
/// the listed directory, skips the collection's own entry, and keeps names
/// + sizes for files.
final class WebDAVPropfindParserTests: XCTestCase {
  private let base = URL(string: "https://nas.local/dav/books/")!

  private func parse(_ xml: String) -> [WebDAVEntry] {
    WebDAVPropfindParser(baseURL: base).parse(Data(xml.utf8))
  }

  func testStandardNextcloudStyleResponse() {
    let entries = parse("""
      <?xml version="1.0"?>
      <d:multistatus xmlns:d="DAV:">
        <d:response>
          <d:href>/dav/books/</d:href>
          <d:propstat>
            <d:prop><d:displayname>books</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
        <d:response>
          <d:href>/dav/books/Author/</d:href>
          <d:propstat>
            <d:prop><d:displayname>Author</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
        <d:response>
          <d:href>/dav/books/book.m4b</d:href>
          <d:propstat>
            <d:prop>
              <d:displayname>My Book</d:displayname>
              <d:resourcetype/>
              <d:getcontentlength>123456789</d:getcontentlength>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      </d:multistatus>
      """)

    /// The collection's own entry is skipped: directory + file remain
    XCTAssertEqual(entries.count, 2)

    let dir = entries.first { $0.isCollection }
    XCTAssertEqual(dir?.name, "Author")
    XCTAssertEqual(dir?.url.absoluteString, "https://nas.local/dav/books/Author/")
    XCTAssertNil(dir?.contentLength)

    let file = entries.first { !$0.isCollection }
    XCTAssertEqual(file?.name, "My Book")
    XCTAssertEqual(file?.contentLength, 123456789)
    XCTAssertNotNil(file?.formattedSize)
  }

  /// A different prefix and no displayname — the filename itself is the name
  func testAlternateNamespaceAndMissingDisplayname() {
    let entries = parse("""
      <?xml version="1.0"?>
      <D:multistatus xmlns:D="DAV:">
        <D:response>
          <D:href>/dav/books/My%20Book.m4b</D:href>
          <D:propstat>
            <D:prop><D:resourcetype></D:resourcetype><D:getcontentlength>42</D:getcontentlength></D:prop>
            <D:status>HTTP/1.1 200 OK</D:status>
          </D:propstat>
        </D:response>
      </D:multistatus>
      """)

    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries.first?.name, "My Book.m4b")
    XCTAssertFalse(entries.first?.isCollection ?? true)
  }

  func testAbsoluteURLHrefResolvesAgainstBase() {
    let entries = parse("""
      <?xml version="1.0"?>
      <d:multistatus xmlns:d="DAV:">
        <d:response>
          <d:href>https://nas.local/dav/books/x.m4b</d:href>
          <d:propstat>
            <d:prop><d:resourcetype/></d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      </d:multistatus>
      """)

    XCTAssertEqual(entries.first?.url.absoluteString, "https://nas.local/dav/books/x.m4b")
  }

  func testMalformedResponseYieldsNoEntries() {
    XCTAssertTrue(parse("not xml").isEmpty)
    XCTAssertTrue(parse("<multistatus></multistatus>").isEmpty)
  }
}
