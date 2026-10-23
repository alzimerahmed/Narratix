//
//  NetworkClient.swift
//  BookPlayer
//
//  Created by gianni.carlo on 23/4/22.
//  Copyright © 2022 BookPlayer LLC. All rights reserved.
//

import Foundation

public protocol NetworkClientProtocol {
  func request<T: Decodable>(
    url: URL,
    method: HTTPMethod,
    parameters: [String: Any]?,
    useKeychain: Bool
  ) async throws -> T

  func request<T: Decodable>(
    path: String,
    method: HTTPMethod,
    parameters: [String: Any]?
  ) async throws -> T

  func upload(
    _ data: Data,
    remoteURL: URL
  ) async throws

  func uploadTask(
    _ fileURL: URL,
    remoteURL: URL,
    taskDescription: String?,
    session: URLSession
  ) async -> URLSessionTask

  /// Managed download by an existing URLSession
  func download(
    url: URL,
    taskDescription: String?,
    session: URLSession
  ) async -> URLSessionTask

  /// Managed download using a fully-built URLRequest (e.g. to carry custom HTTP headers
  /// for integrations behind Cloudflare Access / Authelia / reverse-proxy auth).
  func download(
    request: URLRequest,
    taskDescription: String?,
    session: URLSession
  ) async -> URLSessionTask
}

public class NetworkClient: NetworkClientProtocol, BPLogger {
  /// Http or Https
  let scheme: String = Bundle.main.configurationValue(for: .apiScheme)
  /// Domain
  let host: String = Bundle.main.configurationValue(for: .apiDomain)
  /// Port
  let port: String = Bundle.main.configurationValue(for: .apiPort)
  /// Keychain service for the access token
  let keychain: KeychainServiceProtocol
  /// response decoder
  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  public init(keychain: KeychainServiceProtocol = KeychainService()) {
    self.keychain = keychain
  }

  public func request<T: Decodable>(
    url: URL,
    method: HTTPMethod,
    parameters: [String: Any]?,
    useKeychain: Bool
  ) async throws -> T {
    let request = try buildURLRequest(
      url: url,
      method: method,
      parameters: parameters,
      useKeychain: useKeychain
    )

    return try await executeRequest(request, method: method, parameters: parameters)
  }

  public func request<T: Decodable>(
    path: String,
    method: HTTPMethod,
    parameters: [String: Any]?
  ) async throws -> T {
    let request = try buildURLRequest(path: path, method: method, parameters: parameters)

    return try await executeRequest(request, method: method, parameters: parameters)
  }

  public func download(
    url: URL,
    taskDescription: String?,
    session: URLSession
  ) async -> URLSessionTask {
    await download(
      request: URLRequest(url: url),
      taskDescription: taskDescription,
      session: session
    )
  }

  public func download(
    request: URLRequest,
    taskDescription: String?,
    session: URLSession
  ) async -> URLSessionTask {
    let allTasks = await session.allTasks

    /// Avoid creating a new task if one exists already to avoid double downloads
    if let existingTask = allTasks.first(where: { task in
      task.taskDescription == taskDescription
    }) {
      Self.logger.trace("Existing request for: \(request.url?.path ?? "")")
      return existingTask
    } else {
      Self.logger.trace("[Request] Download \(request.url?.path ?? "")")

      let task = session.downloadTask(with: request)
      task.taskDescription = taskDescription
      task.resume()

      return task
    }
  }

  public func upload(
    _ data: Data,
    remoteURL: URL
  ) async throws {
    var request = URLRequest(url: remoteURL)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.httpMethod = HTTPMethod.put.rawValue
    
    // .path only: presigned URLs carry AWS credentials in the query string.
    Self.logger.trace("[Request] PUT \(remoteURL.path)")
    
    let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
    
    // Cast the response to HTTPURLResponse to check the status code
    if let httpResponse = response as? HTTPURLResponse {
      if !(200...299).contains(httpResponse.statusCode) {
        let errorMessage = String(data: responseData, encoding: .utf8) ?? "No error body"
        // Typed like the rest of the client, so upload failures surface consistently
        throw BookPlayerError.networkError("Upload failed (HTTP \(httpResponse.statusCode)): \(errorMessage)")
      }
    }
  }

  public func uploadTask(
    _ fileURL: URL,
    remoteURL: URL,
    taskDescription: String?,
    session: URLSession
  ) async -> URLSessionTask {
    var request = URLRequest(url: remoteURL)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.httpMethod = HTTPMethod.put.rawValue

    let allTasks = await session.allTasks
    
    /// Avoid creating a new task if one exists already to avoid double uploads
    if let existingTask = allTasks.first(where: { task in
      task.taskDescription == taskDescription
    }) {
      Self.logger.trace("Existing request for: \(remoteURL.path)")
      return existingTask
    } else {
      Self.logger.trace("[Request] PUT \(remoteURL.path)")

      let task = session.uploadTask(with: request, fromFile: fileURL)
      task.taskDescription = taskDescription
      
      return task
    }
  }

  func executeRequest<T: Decodable>(
    _ request: URLRequest,
    method: HTTPMethod,
    parameters: [String: Any]?
  ) async throws -> T {

    Self.logger.trace("[Request] \(method.rawValue) \(request.url?.path)\nParameters: \(parameters?.description)")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpURLResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    Self.logger.trace("[Response] Status \(httpURLResponse.statusCode)\n\(String(data: data, encoding: .utf8))")

    switch httpURLResponse.statusCode {
    case 400...499:
      let error = try self.decoder.decode(ErrorResponse.self, from: data)
      if let code = error.error {
        throw BookPlayerError.networkErrorWithCode(
          message: error.message,
          code: code,
          status: httpURLResponse.statusCode
        )
      } else {
        throw BookPlayerError.networkError(error.message)
      }
    case 500...599:
      if let error = try? self.decoder.decode(ErrorResponse.self, from: data) {
        throw BookPlayerError.networkError(error.message)
      } else {
        throw URLError(.badServerResponse)
      }
    default:
      guard !data.isEmpty else {
        guard
          let emptyResponseType = T.self as? EmptyResponse.Type,
          let emptyValue = emptyResponseType.emptyValue() as? T
        else {
          throw URLError(.cannotParseResponse)
        }

        return emptyValue
      }

      do {
        return try self.decoder.decode(T.self, from: data)
      } catch let error as DecodingError {
        /// Contract drift between the API response and our models is invisible
        /// server-side (the request already returned 2xx), so report it here
        let endpoint = reportableEndpoint(for: request.url)
        ErrorReporter.report(
          title: "Response decoding failed: \(endpoint) (\(T.self).\(Self.codingPathDescription(of: error)))",
          error: error,
          tags: [
            "endpoint": endpoint,
            "response_type": "\(T.self)"
          ]
        )
        throw error
      }
    }
  }

  /// Normalized endpoint for reporting: our API routes are static, but
  /// `request(url:)` can carry presigned storage URLs whose paths embed
  /// user-specific prefixes — redact those, and collapse any dynamic path
  /// component so events stay low-cardinality and free of identifiers
  private func reportableEndpoint(for url: URL?) -> String {
    guard let url else { return "unknown" }
    guard url.host == host else { return "external" }

    let components = url.path.split(separator: "/").map { component -> String in
      let value = String(component)
      if UUID(uuidString: value) != nil || Int(value) != nil {
        return ":id"
      }
      return value
    }
    return "/" + components.joined(separator: "/")
  }

  private static func codingPathDescription(of error: DecodingError) -> String {
    let context: DecodingError.Context?
    switch error {
    case .typeMismatch(_, let errorContext),
        .valueNotFound(_, let errorContext),
        .keyNotFound(_, let errorContext),
        .dataCorrupted(let errorContext):
      context = errorContext
    @unknown default:
      context = nil
    }

    guard let context, !context.codingPath.isEmpty else { return "?" }

    /// Collapse array indices ("Index 3") so the same failure at different
    /// positions groups as one issue
    return context.codingPath
      .map { $0.intValue != nil ? "[]" : $0.stringValue }
      .joined(separator: ".")
  }

  func buildURLRequest(
    url: URL,
    method: HTTPMethod,
    parameters: [String: Any]?,
    useKeychain: Bool = true
  ) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
#if os(watchOS)
    request.setValue("watch.bookplayer.app", forHTTPHeaderField: "origin")
    request.setValue("2022-12-12", forHTTPHeaderField: "accept-version")
#endif

    if useKeychain,
       let accessToken: String = try? keychain.get(.token) {
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    if let parameters = parameters {
      switch method {
      case .post, .put, .delete, .patch:
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
      case .get:
        break
      }
    }

    return request
  }

  func buildURLRequest(
    path: String,
    method: HTTPMethod,
    parameters: [String: Any]?
  ) throws -> URLRequest {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    if let parsedPort = Int(port) {
      components.port = parsedPort
    }
    components.path = path

    if case .get = method,
       let parameters = parameters {
      // Optionals stored as `Any` interpolate as `Optional("…")`, which is what the
      // API had been receiving for every GET `uuid` (it silently failed the server's
      // UUID check and fell back to a path lookup). Unwrap them, and drop absent
      // values instead of sending the literal string "nil".
      components.queryItems = parameters.compactMap { key, value in
        guard let unwrapped = Self.unwrapOptional(value) else { return nil }
        return URLQueryItem(name: key, value: "\(unwrapped)")
      }
      // URLComponents leaves `+` as is, and the API (Express/qs) decodes a literal `+` in
      // a query value as a space: "A+B.mp3" arrived as "A B.mp3", and an S3 upload id
      // carrying `+` would be reported as not found
      components.percentEncodedQuery = components.percentEncodedQuery?
        .replacingOccurrences(of: "+", with: "%2B")
    }

    guard let url = components.url else {
      throw URLError(.badURL)
    }

    return try buildURLRequest(url: url, method: method, parameters: parameters)
  }

  /// `nil` for a nil optional, the wrapped value for a non-nil one, the value itself otherwise.
  private static func unwrapOptional(_ value: Any) -> Any? {
    if case Optional<Any>.none = value { return nil }
    if case Optional<Any>.some(let inner) = value { return inner }
    return value
  }
}

/// Default error message structure
struct ErrorResponse: Decodable {
  let message: String
  let error: String?
}
