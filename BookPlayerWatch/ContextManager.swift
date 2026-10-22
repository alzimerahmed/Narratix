//
//  ContextManager.swift
//  BookPlayerWatch Extension
//
//  Created by gianni.carlo on 18/2/22.
//  Copyright © 2022 BookPlayer LLC. All rights reserved.
//

import BookPlayerWatchKit
import ClockKit
import Foundation
import SwiftUI
import Combine
import WidgetKit

class ContextManager: ObservableObject, BPLogger {
  let watchConnectivityService = WatchConnectivityService()
  private lazy var encoder = JSONEncoder()

  @Published var isConnecting = true
  @Published var isPlaying = false
  @Published var applicationContext: WatchApplicationContext {
    didSet {
      if let oldPath = oldValue.currentItem?.relativePath,
         let currentPath = applicationContext.currentItem?.relativePath,
         oldPath != currentPath {
        handleReloadingWidgets()
      } else if let oldChapterIndex = oldValue.currentItem?.currentChapter.index,
                let currentChapterIndex = applicationContext.currentItem?.currentChapter.index,
                oldChapterIndex != currentChapterIndex {
        handleReloadingWidgets()
      }
    }
  }

  var items: [PlayableItem] {
    return applicationContext.recentItems
  }

  init() {
    self.applicationContext = WatchApplicationContext(
      recentItems: [],
      currentItem: nil,
      rate: 1.0,
      rewindInterval: nil,
      forwardInterval: nil,
      boostVolume: false
    )

    self.watchConnectivityService.didActivateSession = { [weak self] in
      DispatchQueue.main.async {
        self?.isConnecting = false
      }
    }

    self.watchConnectivityService.didReceiveData = { [weak self] messageData in
      guard
        let receivedContext = try? JSONDecoder().decode(WatchApplicationContext.self, from: messageData)
      else {
        return
      }

      DispatchQueue.main.async {
        self?.applicationContext = receivedContext
      }
    }

    self.watchConnectivityService.didReceiveContext = { [weak self] receivedContext in
      guard let context = self?.parseApplicationContext(receivedContext) else {
        return
      }

      DispatchQueue.main.async {
        self?.applicationContext = context
      }
    }

    self.watchConnectivityService.startSession()
  }

  func handleReloadingWidgets() {
    guard
      let watchContextFileURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Constants.ApplicationGroupIdentifier
      )?.appendingPathComponent("WatchContextLastPlayed.data"),
      let applicationContextData = try? encoder.encode(applicationContext.currentItem)
    else { return }

    do {
      try applicationContextData.write(to: watchContextFileURL, options: [.atomic])
      WidgetCenter.shared.reloadAllTimelines()
    } catch {
      Self.logger.trace("Failed to write the watch context data: \(error.localizedDescription)")
    }
  }

  func handleItemSelected(_ item: PlayableItem) {
    guard self.applicationContext.currentItem != item else { return }

    let message = [
      "command": Command.play.rawValue as AnyObject,
      "identifier": item.relativePath as AnyObject
    ]

    self.watchConnectivityService.sendMessage(message: message)
    self.applicationContext.currentItem = item
    self.isPlaying = true
  }

  func handleChapterSelected(_ chapter: PlayableChapter) {
    self.watchConnectivityService.sendMessage(message: [
      "command": Command.chapter.rawValue as AnyObject,
      "start": "\(chapter.start)" as AnyObject
    ])
  }

  func handleSkip(_ direction: SkipDirection) {
    let payload: [String: AnyObject]

    switch direction {
    case .back:
      payload = ["command": Command.skipRewind.rawValue as AnyObject]
    case .forward:
      payload = ["command": Command.skipForward.rawValue as AnyObject]
    }

    self.watchConnectivityService.sendMessage(message: payload)
  }

  func handlePlayPause() {
    var payload = [String: AnyObject]()

    if self.isPlaying {
      payload["command"] = Command.pause.rawValue as AnyObject
    } else {
      payload["command"] = Command.play.rawValue as AnyObject
    }

    if let currentItem = self.applicationContext.currentItem {
      payload["identifier"] = currentItem.relativePath as AnyObject
    }

    self.watchConnectivityService.sendMessage(message: payload)

    self.isPlaying = !self.isPlaying
  }

  func handleSleepTimer(_ state: SleepTimerState) throws {
    var payload = [String: AnyObject]()
    payload["command"] = Command.sleep.rawValue as AnyObject

    switch state {
    case .off:
      payload["seconds"] = "-1" as AnyObject
    case .endOfChapter:
      payload["seconds"] = "-2" as AnyObject
    case .countdown(let timeInterval):
      payload["seconds"] = "\(timeInterval)" as AnyObject
    }

    try self.watchConnectivityService.send(message: payload)
  }

  func requestData() {
    let encoder = JSONEncoder()
    let data = try! encoder.encode(["command": Command.refresh.rawValue])

    self.watchConnectivityService.sendMessageData(
      data: data,
      replyHandler: self.watchConnectivityService.didReceiveData
    )
  }

  // MARK: - Phone library browse + download management (Phase 3f)

  /// Ask the phone for a page of the folder at `path` (nil/empty = library
  /// root). A nil page reply means the phone couldn't answer — unreachable,
  /// or its app isn't listening yet.
  func requestPhoneLibrary(
    path: String?,
    offset: Int,
    completion: @escaping (WatchLibraryPage?) -> Void
  ) {
    /// Without an activated session `sendMessageData` silently no-ops — the
    /// browse screen reads a nil page as "can't reach the phone"
    guard watchConnectivityService.validReachableSession?.activationState == .activated else {
      completion(nil)
      return
    }

    var request: [String: Any] = [
      "command": WatchLibraryCommand.requestLibrary,
      "offset": offset,
    ]
    if let path, !path.isEmpty {
      request["path"] = path
    }

    guard let data = try? JSONSerialization.data(withJSONObject: request) else {
      completion(nil)
      return
    }

    watchConnectivityService.sendMessageData(data: data) { reply in
      let page = try? JSONDecoder().decode(WatchLibraryPage.self, from: reply)
      DispatchQueue.main.async {
        completion(page)
      }
    } errorHandler: { _ in
      DispatchQueue.main.async {
        completion(nil)
      }
    }
  }

  /// Ask the phone to start the item's download (cloud or media server).
  /// `ok` only means the request was accepted — the download itself is
  /// background work on the phone.
  func requestPhoneItemDownload(
    relativePath: String,
    completion: @escaping (Result<Void, WatchItemCommandError>) -> Void
  ) {
    sendItemCommand(
      command: WatchLibraryCommand.downloadItem,
      relativePath: relativePath,
      completion: completion
    )
  }

  /// Ask the phone to offload the item's file — only ever called for rows
  /// whose `canOffload` the phone itself vouched for
  func requestPhoneItemRemoveDownload(
    relativePath: String,
    completion: @escaping (Result<Void, WatchItemCommandError>) -> Void
  ) {
    sendItemCommand(
      command: WatchLibraryCommand.removeDownloadItem,
      relativePath: relativePath,
      completion: completion
    )
  }

  /// Play a browsed phone item through the same remote-control path a recent
  /// row uses — the play command goes to the phone, the reply context update
  /// follows on its own
  func handlePhoneItemSelected(_ item: WatchLibraryItem) {
    watchConnectivityService.sendMessage(message: [
      "command": Command.play.rawValue as AnyObject,
      "identifier": item.relativePath as AnyObject,
    ])
    isPlaying = true
  }

  private func sendItemCommand(
    command: String,
    relativePath: String,
    completion: @escaping (Result<Void, WatchItemCommandError>) -> Void
  ) {
    guard watchConnectivityService.validReachableSession?.activationState == .activated else {
      completion(.failure(.unreachable))
      return
    }

    guard
      let data = try? JSONSerialization.data(withJSONObject: [
        "command": command,
        "identifier": relativePath,
      ])
    else {
      completion(.failure(.failed))
      return
    }

    watchConnectivityService.sendMessageData(data: data) { reply in
      let response = try? JSONDecoder().decode(WatchActionResponse.self, from: reply)
      DispatchQueue.main.async {
        if response?.ok == true {
          completion(.success(()))
        } else {
          completion(.failure(WatchItemCommandError(code: response?.error)))
        }
      }
    } errorHandler: { _ in
      DispatchQueue.main.async {
        completion(.failure(.unreachable))
      }
    }
  }

  /// Remote errors the watch knows how to phrase; anything unrecognized is a
  /// generic failure
  enum WatchItemCommandError: Error {
    case unreachable
    case notFound
    case noRemoteCopy
    case uploadInProgress
    case failed

    init(code: String?) {
      switch code {
      case "notFound": self = .notFound
      case "noRemoteCopy": self = .noRemoteCopy
      case "uploadInProgress": self = .uploadInProgress
      default: self = .failed
      }
    }
  }

  func parseApplicationContext(_ dictionary: [String: Any]) -> WatchApplicationContext {
    let decoder = JSONDecoder()

    var recentItems = [PlayableItem]()
    if let data = dictionary["recentItems"] as? Data {
      recentItems = (try? decoder.decode([PlayableItem].self, from: data)) ?? []
    }

    var currentItem: PlayableItem?
    if let data = dictionary["currentItem"] as? Data {
      currentItem = try? decoder.decode(PlayableItem.self, from: data)
    }

    var rate: Float = 1.0
    if let data = dictionary["rate"] as? Data {
      rate = (try? decoder.decode(Float.self, from: data)) ?? 1.0
    }

    var rewindInterval: Int?
    if let data = dictionary["rewindInterval"] as? Data {
      rewindInterval = try? decoder.decode(Int.self, from: data)
    }

    var forwardInterval: Int?
    if let data = dictionary["forwardInterval"] as? Data {
      forwardInterval = try? decoder.decode(Int.self, from: data)
    }

    var boostVolume = false
    if let data = dictionary["boostVolume"] as? Data {
      boostVolume = (try? decoder.decode(Bool.self, from: data)) ?? false
    }

    return WatchApplicationContext(
      recentItems: recentItems,
      currentItem: currentItem,
      rate: rate,
      rewindInterval: rewindInterval,
      forwardInterval: forwardInterval,
      boostVolume: boostVolume
    )
  }
}

/// Playback controls (companion version)
extension ContextManager {
  var rate: Float {
    applicationContext.rate
  }
  
  var boostVolume: Bool {
    applicationContext.boostVolume
  }

  func handleBoostVolumeToggle() {
    self.applicationContext.boostVolume = !self.applicationContext.boostVolume

    self.watchConnectivityService.sendMessage(message: [
      "command": Command.boostVolume.rawValue as AnyObject,
      "isOn": "\(self.applicationContext.boostVolume)" as AnyObject
    ])
  }

  func handleNewSpeed(_ rate: Float) {
    let roundedValue = round(rate * 100) / 100.0

    guard roundedValue >= 0.5 && roundedValue <= 4.0 else { return }

    self.watchConnectivityService.sendMessage(message: [
      "command": Command.speed.rawValue as AnyObject,
      "rate": "\(rate)" as AnyObject
    ])

    self.applicationContext.rate = roundedValue
  }

  func handleNewSpeedJump() {
    let rate: Float

    if self.applicationContext.rate == 4.0 {
      rate = 0.5
    } else {
      rate = min(self.applicationContext.rate + 0.5, 4.0)
    }

    let roundedValue = round(rate * 100) / 100.0

    self.watchConnectivityService.sendMessage(message: [
      "command": Command.speed.rawValue as AnyObject,
      "rate": "\(rate)" as AnyObject
    ])

    self.applicationContext.rate = roundedValue
  }
}
