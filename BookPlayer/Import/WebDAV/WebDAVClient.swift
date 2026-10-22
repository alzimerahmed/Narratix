//
//  WebDAVClient.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation

/// One member of a WebDAV directory listing
struct WebDAVEntry: Identifiable, Hashable, Sendable {
  /// The resolved resource URL — unique within a listing
  var id: URL { url }
  let url: URL
  /// Display name (displayname, or the decoded last path component)
  let name: String
  let isCollection: Bool
  let contentLength: Int64?

  var formattedSize: String? {
    guard let contentLength, !isCollection else { return nil }
    return ByteCountFormatter.string(fromByteCount: contentLength, countStyle: .file)
  }
}

enum WebDAVError: LocalizedError {
  /// No scheme/host, or a scheme that isn't http(s)
  case invalidURL
  /// 401/403 — username or password rejected
  case unauthorized
  /// 404 on a PROPFIND — the URL exists but isn't a WebDAV collection
  case notFound
  case serverError(Int)
  case notWebDAV

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "webdav_error_invalid_url".localized
    case .unauthorized:
      return "webdav_error_unauthorized".localized
    case .notFound:
      return "webdav_error_not_found".localized
    case .serverError(let code):
      return String.localizedStringWithFormat("webdav_error_server".localized, code)
    case .notWebDAV:
      return "webdav_error_not_webdav".localized
    }
  }
}

/// A minimal WebDAV client for the import flow: PROPFIND (Depth: 1) listings
/// parsed with `XMLParser`, GET downloads streamed to disk. Plain `URLSession`,
/// Basic auth — no dependencies. Credentials go on requests to the connection's
/// own URLs and nowhere else.
final class WebDAVClient: NSObject, BPLogger, @unchecked Sendable {
  /// Audio/archive types a folder download keeps — everything else (nfo, cues,
  /// cover art the server may carry) is left on the server
  static let importableExtensions: Set<String> = [
    "mp3", "m4a", "m4b", "aac", "aax", "aaxc", "wav", "aif", "aiff", "caf",
    "flac", "opus", "ogg", "oga", "mp4", "m4v", "mov", "avi", "zip", "lpf",
  ]

  let connection: WebDAVConnection
  private let session: URLSession

  init(connection: WebDAVConnection, session: URLSession = .shared) {
    self.connection = connection
    self.session = session
  }

  /// Normalize what the user typed into a server URL: https is assumed when no
  /// scheme is given, a trailing slash added so relative hrefs resolve under it
  static func normalizeURL(_ raw: String) -> URL? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if !text.contains("://") {
      text = "https://" + text
    }
    guard
      let url = URL(string: text),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      url.host != nil
    else { return nil }
    /// Credentials pasted into the address (user:pass@host) don't belong in
    /// the stored URL — the username/password fields carry them instead
    if url.user != nil || url.password != nil {
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      components?.user = nil
      components?.password = nil
      return components?.url
    }
    return url
  }

  // MARK: - Requests

  /// Authorization header for the connection's own server. Never attaches to
  /// anything else — the check compares scheme, host AND effective port, so
  /// an http or odd-port URL on the same host gets no credentials
  private func authorizedRequest(url: URL, method: String, depth: String? = nil, body: Data? = nil) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    if let depth {
      request.setValue(depth, forHTTPHeaderField: "Depth")
    }
    if let body {
      request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }
    guard
      !connection.username.isEmpty,
      connection.url.scheme?.lowercased() == url.scheme?.lowercased(),
      connection.url.host?.lowercased() == url.host?.lowercased(),
      Self.effectivePort(of: connection.url) == Self.effectivePort(of: url)
    else { return request }
    let credentials = "\(connection.username):\(connection.password)"
    if let data = credentials.data(using: .utf8) {
      request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  /// The port the URL answers on — explicit, or the scheme's default
  private static func effectivePort(of url: URL) -> Int? {
    if let port = url.port { return port }
    switch url.scheme?.lowercased() {
    case "https": return 443
    case "http": return 80
    default: return nil
    }
  }

  private static let propfindBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:displayname/>
        <d:resourcetype/>
        <d:getcontentlength/>
      </d:prop>
    </d:propfind>
    """

  // MARK: - Listing

  /// PROPFIND Depth:1 — the entries inside `url`, excluding the collection itself
  func listDirectory(at url: URL) async throws -> [WebDAVEntry] {
    var directory = url
    if !url.absoluteString.hasSuffix("/") {
      directory = url.appendingPathComponent("")
    }

    let request = authorizedRequest(
      url: directory,
      method: "PROPFIND",
      depth: "1",
      body: Self.propfindBody.data(using: .utf8)
    )

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw BookPlayerError.networkError(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw WebDAVError.notWebDAV
    }
    switch http.statusCode {
    case 207:
      break
    case 401, 403:
      throw WebDAVError.unauthorized
    case 404:
      throw WebDAVError.notFound
    case 400..<600:
      throw WebDAVError.serverError(http.statusCode)
    default:
      throw WebDAVError.notWebDAV
    }

    let parser = WebDAVPropfindParser(baseURL: directory)
    return parser.parse(data)
  }

  /// Every importable file inside a collection, recursively. Returns
  /// (resource URL, path relative to the collection) pairs so the download
  /// can rebuild the folder structure.
  func collectFiles(under collection: WebDAVEntry) async throws -> [(url: URL, relativePath: String)] {
    let entries = try await listDirectory(at: collection.url)
    var files: [(URL, String)] = []
    for entry in entries {
      if entry.isCollection {
        for file in try await collectFiles(under: entry) {
          files.append((file.url, "\(entry.name)/\(file.relativePath)"))
        }
      } else if Self.importableExtensions.contains(entry.url.pathExtension.lowercased()) {
        files.append((entry.url, entry.name))
      }
    }
    return files
  }

  // MARK: - Download

  /// Stream a file to `destination`, reporting 0…1 progress. The holding folder
  /// must already exist. Cancelled tasks delete their partial file.
  func download(
    _ resourceURL: URL,
    to destination: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    let request = authorizedRequest(url: resourceURL, method: "GET")

    let location = try await withCheckedThrowingContinuation { continuation in
      let delegate = DownloadSessionDelegate(
        progress: progress,
        completion: continuation
      )
      let session = URLSession(
        configuration: .default,
        delegate: delegate,
        delegateQueue: nil
      )
      delegate.owningSession = session
      session.downloadTask(with: request).resume()
    }

    try FileManager.default.moveItem(at: location, to: destination)
  }
}

/// One-shot session delegate: finishes a single download, reports progress,
/// then invalidates its session. Retained by the URLSession until then.
private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  let progress: @Sendable (Double) -> Void
  private let continuation: CheckedContinuation<URL, Error>
  /// Strong until completion, so the session outlives the awaiting scope
  var owningSession: URLSession?

  init(progress: @escaping @Sendable (Double) -> Void, completion: CheckedContinuation<URL, Error>) {
    self.progress = progress
    self.continuation = completion
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    /// A non-2xx still "downloads" — the file is the error body
    if let response = downloadTask.response as? HTTPURLResponse,
      !(200..<300).contains(response.statusCode) {
      try? FileManager.default.removeItem(at: location)
      if response.statusCode == 401 || response.statusCode == 403 {
        continuation.resume(throwing: WebDAVError.unauthorized)
      } else {
        continuation.resume(throwing: WebDAVError.serverError(response.statusCode))
      }
      return
    }
    /// The temp file is removed when the delegate returns — move it aside
    /// before resuming the continuation
    let staging = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    do {
      try FileManager.default.moveItem(at: location, to: staging)
      continuation.resume(returning: staging)
    } catch {
      continuation.resume(throwing: error)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    session.finishTasksAndInvalidate()
    owningSession = nil
    /// didCompleteWithError runs after didFinishDownloadingTo on success —
    /// resume has already happened there, and a nil error means nothing failed
    guard error != nil else { return }
    if let response = task.response as? HTTPURLResponse,
      response.statusCode == 401 || response.statusCode == 403 {
      continuation.resume(throwing: WebDAVError.unauthorized)
    } else {
      continuation.resume(throwing: error ?? BookPlayerError.networkError("Download failed"))
    }
  }
}
