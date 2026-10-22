//
//  PhoneWatchConnectivityService.swift
//  BookPlayer
//
//  Created by gianni.carlo on 14/3/22.
//  Copyright © 2022 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Combine
import WatchConnectivity

public class PhoneWatchConnectivityService: NSObject, WCSessionDelegate {
  let libraryService: LibraryServiceProtocol
  let playbackService: PlaybackServiceProtocol
  let playerManager: PlayerManagerProtocol
  var accountService: AccountServiceProtocol?
  /// Needed only for the watch's download-management requests — optional for
  /// the same reason as `accountService`: `SyncService` is built beside this
  /// service at CoreServices setup, not inside it
  var syncService: SyncServiceProtocol?
  /// Flag to avoid calling activate more than once from outside the service
  var didStartSession = false
  /// Flag used to register observers only once
  var didRegisterObservers = false

  private var disposeBag = Set<AnyCancellable>()

  public init(
    libraryService: LibraryServiceProtocol,
    playbackService: PlaybackServiceProtocol,
    playerManager: PlayerManagerProtocol
  ) {
    self.libraryService = libraryService
    self.playbackService = playbackService
    self.playerManager = playerManager

    super.init()
  }

  public func setAccountService(_ accountService: AccountServiceProtocol) {
    self.accountService = accountService
  }

  public func setSyncService(_ syncService: SyncServiceProtocol) {
    self.syncService = syncService
  }

  func bindObservers() {
    NotificationCenter.default.publisher(for: .bookReady, object: nil)
      .sink(receiveValue: { [weak self] notification in
        guard
          let self = self,
          let loaded = notification.userInfo?["loaded"] as? Bool,
          loaded == true
        else {
          return
        }

        self.sendApplicationContext()
      })
      .store(in: &disposeBag)

    NotificationCenter.default.publisher(for: .chapterChange, object: nil)
      .sink(receiveValue: { [weak self] _ in
        self?.sendApplicationContext()
      })
      .store(in: &disposeBag)

    NotificationCenter.default.publisher(for: .bookPlayed, object: nil)
      .sink(receiveValue: { [weak self] notification in
        guard
          let self = self,
          self.session?.activationState == .activated,
          let currentItem = notification.userInfo?["book"] as? PlayableItem
        else {
          return
        }

        self.sendMessage(message: [
          "command": "play" as AnyObject,
          "identifier": currentItem.relativePath as AnyObject
        ])
      })
      .store(in: &disposeBag)

    NotificationCenter.default.publisher(for: .bookPaused, object: nil)
      .sink(receiveValue: { [weak self] _ in
        guard
          self?.session?.activationState == .activated
        else {
          return
        }

        self?.sendMessage(message: [
          "command": "pause" as AnyObject,
        ])
      })
      .store(in: &disposeBag)
  }

  private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

  public var validSession: WCSession? {
    if let session = self.session, session.isPaired, session.isWatchAppInstalled {
      return session
    } else {
      return nil
    }
  }

  public func startSession(_ delegate: WCSessionDelegate? = nil) {
    guard !self.didStartSession else { return }

    self.didStartSession = true
    self.session?.delegate = delegate ?? self
    self.session?.activate()
  }

  public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    self.sendApplicationContext()

    // Register observers only once
    if !didRegisterObservers {
      didRegisterObservers = true
      bindObservers()
    }
  }

  public func sessionDidBecomeInactive(_ session: WCSession) {}

  public func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  public func sendApplicationContext() {
    guard self.validSession != nil else { return }

    let applicationContext = self.generateApplicationContext()

    try? self.updateApplicationContext(
      applicationContext: self.getDictionaryFromContext(applicationContext)
    )

    guard
      self.session?.activationState == .activated,
      let applicationContextData = try? JSONEncoder().encode(applicationContext)
    else { return }

    self.sendMessageData(data: applicationContextData)
  }

  public func generateApplicationContext() -> WatchApplicationContext {
    var recentItems = [PlayableItem]()
    if let recentBooks = self.libraryService.getLastPlayedItems(limit: 20) {
      recentItems = recentBooks.compactMap({ [weak self] in
        try? self?.playbackService.getPlayableItem(from: $0)
      })
    }

    return WatchApplicationContext(
      recentItems: recentItems,
      currentItem: self.playerManager.currentItem,
      rate: self.playerManager.currentSpeed,
      rewindInterval: Int(PlayerManager.rewindInterval),
      forwardInterval: Int(PlayerManager.forwardInterval),
      boostVolume: UserDefaults.standard.bool(forKey: Constants.UserDefaults.boostVolumeEnabled)
    )
  }

  public func getDictionaryFromContext(_ applicationContext: WatchApplicationContext) -> [String: AnyObject] {
    let encoder = JSONEncoder()

    return [
      "recentItems": (try? encoder.encode(applicationContext.recentItems)) as AnyObject,
      "currentItem": (try? encoder.encode(applicationContext.currentItem)) as AnyObject,
      "rate": (try? encoder.encode(applicationContext.rate)) as AnyObject,
      "rewindInterval": (try? encoder.encode(applicationContext.rewindInterval)) as AnyObject,
      "forwardInterval": (try? encoder.encode(applicationContext.forwardInterval)) as AnyObject,
      "boostVolume": (try? encoder.encode(applicationContext.boostVolume)) as AnyObject
    ]
  }
}

// MARK: Application Context

// use when your app needs only the latest information
// if the data was not sent, it will be replaced
extension PhoneWatchConnectivityService {
  // Sender
  public func updateApplicationContext(applicationContext: [String: AnyObject]) throws {
    if let session = validSession {
      do {
        try session.updateApplicationContext(applicationContext)
      } catch {
        throw error
      }
    }
  }
}

// MARK: Interactive Messaging

extension PhoneWatchConnectivityService {
  // Live messaging! App has to be reachable when sending messages from the phone
  public var validReachableSession: WCSession? {
    if let session = validSession, session.isReachable {
      return session
    }

    return nil
  }

  // Sender
  public func sendMessage(message: [String: AnyObject],
                          replyHandler: (([String: Any]) -> Void)? = nil,
                          errorHandler: ((Error) -> Void)? = nil) {
    self.validReachableSession?.sendMessage(message, replyHandler: replyHandler, errorHandler: errorHandler)
  }

  public func sendMessageData(data: Data,
                              replyHandler: ((Data) -> Void)? = nil,
                              errorHandler: ((Error) -> Void)? = nil) {
    self.validReachableSession?.sendMessageData(data, replyHandler: replyHandler, errorHandler: errorHandler)
  }

  public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    // Handle auth request from Watch
    if let command = message["command"] as? String, command == "requestAuth" {
      handleAuthRequest(replyHandler: replyHandler)
      return
    }

    NotificationCenter.default.post(name: .messageReceived, object: nil, userInfo: message)
    replyHandler(["success": true])
  }

  private func handleAuthRequest(replyHandler: @escaping ([String: Any]) -> Void) {
    guard let accountService = accountService else {
      replyHandler(["error": "serviceUnavailable"])
      return
    }

    guard let account = accountService.getAccount(),
          !account.id.isEmpty else {
      replyHandler(["error": "notSignedIn"])
      return
    }

    let keychain = KeychainService()
    guard let token: String = try? keychain.get(.token) else {
      replyHandler(["error": "noToken"])
      return
    }

    replyHandler([
      "token": token,
      "email": account.email,
      "accountId": account.id,
      "hasSubscription": account.hasSubscription,
      "donationMade": account.donationMade
    ])
  }

  public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    NotificationCenter.default.post(name: .messageReceived, object: nil, userInfo: message)
  }

  /// Only used for refresh command on the phone side
  public func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
    /// The watch's library-browse requests answer here (literal command keys —
    /// see `WatchLibraryCommand`); the playback-sync contract via
    /// `CommandParser`/`Command` is untouched
    if let jsonObject = try? JSONSerialization.jsonObject(with: messageData, options: .mutableLeaves) as? [String: Any],
       let command = jsonObject["command"] as? String,
       command != Command.refresh.rawValue {
      handleWatchLibraryRequest(command: command, message: jsonObject, replyHandler: replyHandler)
      return
    }

    guard
      let jsonObject = try? JSONSerialization.jsonObject(with: messageData, options: .mutableLeaves) as? [String: Any],
      let action = CommandParser.parse(jsonObject),
      action.command == .refresh
    else {
      replyHandler(Data())
      return
    }

    let applicationContext = generateApplicationContext()

    guard let applicationContextData = try? JSONEncoder().encode(applicationContext) else { return }

    replyHandler(applicationContextData)
  }
}

// MARK: - Watch library browse + download management (Phase 3f)
extension PhoneWatchConnectivityService {
  /// Page size cap for `requestLibrary` — the reply rides `sendMessageData`,
  /// whose payload budget is a few hundred KB; 50 compact rows stay well
  /// inside it even with long titles
  private static let libraryPageLimit = 50

  private func handleWatchLibraryRequest(
    command: String,
    message: [String: Any],
    replyHandler: @escaping (Data) -> Void
  ) {
    switch command {
    case WatchLibraryCommand.requestLibrary:
      replyHandler(buildLibraryPage(from: message))
    case WatchLibraryCommand.downloadItem:
      guard let relativePath = message["identifier"] as? String else {
        reply(response: WatchActionResponse(ok: false, error: "notFound"), to: replyHandler)
        return
      }
      handleDownloadRequest(relativePath: relativePath, replyHandler: replyHandler)
    case WatchLibraryCommand.removeDownloadItem:
      guard let relativePath = message["identifier"] as? String else {
        reply(response: WatchActionResponse(ok: false, error: "notFound"), to: replyHandler)
        return
      }
      handleRemoveDownloadRequest(relativePath: relativePath, replyHandler: replyHandler)
    default:
      replyHandler(Data())
    }
  }

  private func buildLibraryPage(from message: [String: Any]) -> Data {
    let path = (message["path"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let offset = max((message["offset"] as? Int) ?? 0, 0)
    let limit = min((message["limit"] as? Int) ?? Self.libraryPageLimit, Self.libraryPageLimit)

    let items = libraryService.fetchContents(at: path, limit: limit, offset: offset) ?? []
    let page = WatchLibraryPage(
      items: items.map(watchItem(for:)),
      hasMore: items.count == limit
    )

    return (try? JSONEncoder().encode(page)) ?? Data()
  }

  /// Download state + offload eligibility, evaluated the same way the phone's
  /// storage screen does: a state only exists when the item has somewhere to
  /// download FROM (sync on, or a media-server stream link), and offloading
  /// only ever applies to a downloaded item with a remote copy
  private func watchItem(for item: SimpleLibraryItem) -> WatchLibraryItem {
    let streamsFromServer = item.externalResources?.streamingResource != nil
    let remoteBacked = (syncService?.isActive == true) || streamsFromServer

    var stateString: String?
    var canOffload = false
    if remoteBacked, let downloadState = syncService?.getDownloadState(for: item) {
      switch downloadState {
      case .notDownloaded:
        stateString = "notDownloaded"
      case .downloading:
        stateString = "downloading"
      case .downloaded:
        stateString = "downloaded"
        canOffload = offloadAllowed(for: item, streamsFromServer: streamsFromServer)
      }
    }

    return WatchLibraryItem(
      relativePath: item.relativePath,
      title: item.title,
      details: item.details,
      type: item.type.rawValue,
      isFinished: item.isFinished,
      percentCompleted: item.percentCompleted,
      duration: item.duration,
      downloadState: stateString,
      canOffload: canOffload
    )
  }

  /// The storage screen's rule, shared by the row flag and the remove request:
  /// the local file may only go when a copy remains to come back to — a cloud
  /// `remoteURL` or a media-server stream link. `remoteBacked` alone isn't
  /// enough: sync can be on while this item was never uploaded
  private func offloadAllowed(for item: SimpleLibraryItem, streamsFromServer: Bool) -> Bool {
    item.remoteURL != nil || streamsFromServer
  }

  /// Ask the phone to fetch the item's file from the cloud or its media
  /// server. Replies `ok` once the request is ACCEPTED, then kicks the
  /// download off — `downloadRemoteFiles` resolves remote URLs over the
  /// network before returning, and letting the watch wait on it would trip
  /// the reply timeout and cry "unreachable" while a download runs fine.
  /// A resolution failure after the ack surfaces on the next page load,
  /// which reads the real download state.
  private func handleDownloadRequest(
    relativePath: String,
    replyHandler: @escaping (Data) -> Void
  ) {
    guard
      let item = libraryService.getSimpleItem(with: relativePath),
      let syncService
    else {
      reply(response: WatchActionResponse(ok: false, error: "notFound"), to: replyHandler)
      return
    }

    guard syncService.isActive || item.externalResources?.streamingResource != nil else {
      reply(response: WatchActionResponse(ok: false, error: "noRemoteCopy"), to: replyHandler)
      return
    }

    reply(response: WatchActionResponse(ok: true), to: replyHandler)

    Task { @MainActor in
      try? await syncService.downloadRemoteFiles(for: item)
    }
  }

  /// Remove the item's local file on the phone — offload, never delete: the
  /// request is refused unless a remote copy remains to come back to, and a
  /// queued or running upload keeps the file in place too
  private func handleRemoveDownloadRequest(
    relativePath: String,
    replyHandler: @escaping (Data) -> Void
  ) {
    guard
      let item = libraryService.getSimpleItem(with: relativePath),
      let syncService
    else {
      reply(response: WatchActionResponse(ok: false, error: "notFound"), to: replyHandler)
      return
    }

    Task { @MainActor in
      /// An upload in flight means the remote copy isn't real yet — same
      /// guard the storage screen applies before offloading. The prefix match
      /// also catches a child's queued upload under a folder or bound book,
      /// whose own path is only the container's
      if await syncService.hasUploadTask(matchingPrefix: relativePath) {
        self.reply(response: WatchActionResponse(ok: false, error: "uploadInProgress"), to: replyHandler)
        return
      }

      /// Verify offloading here too — the watch only offers the action for
      /// rows the phone flagged `canOffload`, but a file is never deleted on
      /// another device's say-so without the remote-copy evidence holding up
      let streamsFromServer = item.externalResources?.streamingResource != nil
      let remoteBacked = syncService.isActive || streamsFromServer
      guard
        remoteBacked,
        syncService.getDownloadState(for: item) == .downloaded,
        offloadAllowed(for: item, streamsFromServer: streamsFromServer)
      else {
        self.reply(response: WatchActionResponse(ok: false, error: "noRemoteCopy"), to: replyHandler)
        return
      }

      do {
        let fileURL = item.fileURL
        try FileManager.default.removeItem(at: fileURL)
        /// Bound books and folders keep an empty backing folder — same shape
        /// `handleOffloading` leaves behind
        if item.type == .bound || item.type == .folder {
          try FileManager.default.createDirectory(
            at: fileURL,
            withIntermediateDirectories: false,
            attributes: nil
          )
        }
        ArtworkService.artworkUpdatePublisher.send(relativePath)
        self.reply(response: WatchActionResponse(ok: true), to: replyHandler)
      } catch {
        self.reply(response: WatchActionResponse(ok: false, error: "failed"), to: replyHandler)
      }
    }
  }

  private func reply(response: WatchActionResponse, to replyHandler: (Data) -> Void) {
    replyHandler((try? JSONEncoder().encode(response)) ?? Data())
  }
}
