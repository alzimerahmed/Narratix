//
//  WebDAVBrowserViewModel.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Combine
import Foundation

/// Drives `WebDAVBrowserView`: connect form → directory browser → download
/// staging. Confirm hands the staged files to an `ImportOperation` — the same
/// step the Transfer from Computer flow takes — so the import screen never
/// opens and the library goes straight to its placement prompt.
@MainActor
final class WebDAVBrowserViewModel: ObservableObject, BPLogger {
  /// Where downloads are staged for the import to take. The import owns the
  /// folder and deletes it when done; cancelling the browser removes it here.
  static let holdingRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("WebDAVImport", isDirectory: true)

  enum Phase: Equatable {
    case connect
    case browse
    case downloading
  }

  // MARK: - Connection form
  @Published var serverURL = ""
  @Published var username = ""
  @Published var password = ""
  /// Passwords go to the Keychain — the toggle decides whether they STAY
  /// there between sessions; it never reads from anywhere else
  @Published var rememberCredentials = true

  // MARK: - Browse state
  @Published private(set) var phase: Phase = .connect
  /// Directories between the connection root and where the user is; empty = root
  @Published private(set) var path: [WebDAVEntry] = []
  @Published private(set) var entries: [WebDAVEntry] = []
  /// Selected resource URLs (files AND folders — folders download recursively)
  @Published var selection = Set<URL>()
  @Published private(set) var isLoading = false
  @Published var error: Error?
  /// An explicit http:// URL waiting on the cleartext warning's answer
  @Published var insecureURL: URL?

  /// Download staging progress: "file i of n" plus the current file's fraction
  struct DownloadProgress: Equatable {
    var current: Int
    var total: Int
    var fraction: Double
    var currentName: String
  }
  @Published private(set) var downloadProgress: DownloadProgress?

  private var connection: WebDAVConnection?
  private var client: WebDAVClient?
  private var downloadTask: Task<Void, Never>?
  /// The session's staging folder while downloads run — nil once the import
  /// owns it, so a dismiss can't delete files the operation is reading
  private var stagingRoot: URL?

  let importManager: ImportManager
  let libraryService: LibraryServiceProtocol
  let keychain: KeychainServiceProtocol

  init(
    importManager: ImportManager,
    libraryService: LibraryServiceProtocol,
    keychain: KeychainServiceProtocol = KeychainService()
  ) {
    self.importManager = importManager
    self.libraryService = libraryService
    self.keychain = keychain
  }

  /// A saved connection exists — the connect form can offer "Forget server"
  var hasSavedConnection: Bool {
    (try? keychain.get(.webdavConnection) as WebDAVConnection?) != nil
  }

  /// On appear: restore the saved connection and go straight to browse
  func restore() {
    guard phase == .connect, connection == nil else { return }
    guard let saved: WebDAVConnection = try? keychain.get(.webdavConnection) else { return }
    connection = saved
    client = WebDAVClient(connection: saved)
    serverURL = saved.url.absoluteString
    username = saved.username
    Task { await open(url: saved.url) }
  }

  // MARK: - Connect

  func connect() async {
    guard let url = WebDAVClient.normalizeURL(serverURL) else {
      error = WebDAVError.invalidURL
      return
    }

    /// An explicit http:// address sends the password cleartext — hold for
    /// the warning's "Connect anyway" instead of connecting blind
    if url.scheme?.lowercased() == "http" {
      insecureURL = url
      return
    }

    await connect(to: url)
  }

  /// "Connect anyway" on the cleartext warning
  func confirmInsecureConnect() {
    guard let url = insecureURL else { return }
    insecureURL = nil
    Task { await connect(to: url) }
  }

  private func connect(to url: URL) async {
    let connection = WebDAVConnection(url: url, username: username, password: password)
    self.connection = connection
    let client = WebDAVClient(connection: connection)
    self.client = client

    isLoading = true
    defer { isLoading = false }
    do {
      _ = try await client.listDirectory(at: url)
      self.phase = .browse
      if rememberCredentials {
        try? keychain.set(connection, key: .webdavConnection)
      } else {
        try? keychain.remove(.webdavConnection)
      }
    } catch {
      self.error = error
      self.connection = nil
      self.client = nil
    }
  }

  /// "Forget server": drop the saved credentials and stay on the form
  func forgetConnection() {
    try? keychain.remove(.webdavConnection)
    connection = nil
    client = nil
    serverURL = ""
    username = ""
    password = ""
    phase = .connect
    path = []
    entries = []
    selection = []
  }

  // MARK: - Browse

  /// The directory being shown — top of the stack, or the connection root
  private var currentURL: URL {
    path.last?.url ?? connection?.url ?? URL(fileURLWithPath: "/")
  }

  private func open(url: URL) async {
    guard let client else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let entries = try await client.listDirectory(at: url)
      self.entries = entries.sorted {
        /// Folders first, then Finder-style ordering
        if $0.isCollection != $1.isCollection { return $0.isCollection }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      if phase == .connect { phase = .browse }
    } catch {
      self.error = error
    }
  }

  func refresh() async {
    await open(url: currentURL)
  }

  func navigate(to entry: WebDAVEntry) {
    guard entry.isCollection else { return }
    path.append(entry)
    selection = []
    Task { await open(url: entry.url) }
  }

  func navigateUp() {
    guard !path.isEmpty else { return }
    path.removeLast()
    selection = []
    Task { await open(url: currentURL) }
  }

  /// A folder's checkbox means "everything under it" — download time resolves it
  func toggle(_ entry: WebDAVEntry) {
    if selection.contains(entry.url) {
      selection.remove(entry.url)
    } else {
      selection.insert(entry.url)
    }
  }

  // MARK: - Import

  var canImport: Bool { !selection.isEmpty && phase == .browse }

  /// Download the selection into holding and hand it to the import pipeline.
  /// Sequential — a NAS answers one stream fine and parallel bursts trip
  /// rate limits on home servers.
  func importSelection() {
    guard let client, let connection else { return }
    let selected = entries.filter { selection.contains($0.url) }

    phase = .downloading
    downloadProgress = DownloadProgress(current: 0, total: 0, fraction: 0, currentName: "")

    downloadTask = Task { [weak self] in
      guard let self else { return }
      let holding = Self.holdingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
      self.stagingRoot = holding
      do {
        try FileManager.default.createDirectory(at: holding, withIntermediateDirectories: true)
      } catch {
        self.error = error
        self.phase = .browse
        return
      }

      /// Resolve selections to concrete files first so the total count is real:
      /// selected folders expand to their importable contents
      var plan: [(url: URL, relativePath: String)] = []
      var topLevel = [URL]()
      do {
        for entry in selected {
          if entry.isCollection {
            let files = try await client.collectFiles(under: entry)
            for file in files {
              plan.append((file.url, "\(entry.name)/\(file.relativePath)"))
            }
            if !files.isEmpty {
              topLevel.append(holding.appendingPathComponent(entry.name, isDirectory: true))
            }
          } else {
            plan.append((entry.url, entry.name))
            topLevel.append(holding.appendingPathComponent(entry.name))
          }
        }
      } catch {
        self.error = error
        self.phase = .browse
        try? FileManager.default.removeItem(at: holding)
        return
      }

      var failed = 0
      for (index, file) in plan.enumerated() {
        /// A dismiss deletes staging — without this check the create below
        /// recreates it for a batch the user already cancelled
        if Task.isCancelled || !FileManager.default.fileExists(atPath: holding.path) {
          break
        }
        let destination = holding.appendingPathComponent(file.relativePath)
        do {
          try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
        } catch {
          failed += 1
          continue
        }

        let name = file.url.lastPathComponent
        await MainActor.run {
          self.downloadProgress = DownloadProgress(
            current: index + 1,
            total: plan.count,
            fraction: 0,
            currentName: name
          )
        }

        do {
          try await client.download(file.url, to: destination) { [weak self] fraction in
            Task { @MainActor in
              self?.downloadProgress?.fraction = fraction
            }
          }
        } catch {
          failed += 1
          Self.logger.error("WebDAV download failed for \(name): \(error.localizedDescription)")
        }
      }

      /// Cancelled mid-batch, or staging deleted under the loop: the partial
      /// files never reach the import — clean up and stay in the browser
      guard !Task.isCancelled,
        FileManager.default.fileExists(atPath: holding.path)
      else {
        try? FileManager.default.removeItem(at: holding)
        self.stagingRoot = nil
        self.phase = .browse
        self.downloadProgress = nil
        return
      }

      /// Nothing got down — report and stay in the browser
      let imported = topLevel.filter { FileManager.default.fileExists(atPath: $0.path) }
      guard !imported.isEmpty else {
        try? FileManager.default.removeItem(at: holding)
        self.stagingRoot = nil
        self.phase = .browse
        self.downloadProgress = nil
        if failed > 0 {
          self.error = BookPlayerError.networkError("webdav_download_failed".localized)
        }
        return
      }

      if failed > 0 {
        Self.logger.error("WebDAV import dropped \(failed) of \(plan.count) files")
      }

      self.importManager.operationPublisher.send(
        ImportOperation(files: imported, libraryService: self.libraryService, ownedSourceRoot: holding)
      )
      /// Ownership moved to the operation — a dismiss after this must not clean it
      self.stagingRoot = nil
      self.downloadProgress = nil
      /// The sheet dismisses; the import and its placement prompt carry on
    }
  }

  /// Sheet dismissed mid-download or mid-browse: stop work and drop staging.
  /// After `importSelection` handed off, the import owns the holding folder.
  func dismissFlow() {
    downloadTask?.cancel()
    downloadTask = nil
    if let stagingRoot {
      try? FileManager.default.removeItem(at: stagingRoot)
      self.stagingRoot = nil
    }
  }
}
