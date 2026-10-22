//
//  WatchLibraryItem.swift
//  BookPlayerKit
//
//  Created by Gianni Carlo on 3/8/26.
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//
//

import Foundation

/// Command keys for the watch→phone library-browse channel. Literal strings
/// (not `Command` cases): they only live inside `sendMessageData` requests —
/// routing through `CommandParser`/`Action` would put them in the URL-scheme
/// and `.messageReceived` contracts they don't belong to.
public enum WatchLibraryCommand {
  /// `{command, path?, offset?, limit?}` → reply `WatchLibraryPage` JSON
  public static let requestLibrary = "requestLibrary"
  /// `{command, identifier}` → reply `WatchActionResponse` JSON; asks the
  /// phone to download the item (cloud or media-server copy)
  public static let downloadItem = "downloadItem"
  /// `{command, identifier}` → reply `WatchActionResponse` JSON; removes the
  /// item's local file on the phone (only ever sent when `canOffload`)
  public static let removeDownloadItem = "removeDownloadItem"
}

/// The phone library row a watch shows when browsing the phone's contents.
/// Deliberately compact: it crosses `sendMessageData`, whose payload budget
/// is a few hundred KB — a 50-item page stays a fraction of that.
public struct WatchLibraryItem: Codable, Hashable, Identifiable {
  public var id: String { relativePath }

  public let relativePath: String
  public let title: String
  /// Author line for books, generated summary for folders — same source as
  /// `SimpleLibraryItem.details`
  public let details: String
  /// `SimpleItemType.rawValue` (kept as Int16 so the payload doesn't depend
  /// on the enum's Codable conformance)
  public let type: Int16
  public let isFinished: Bool
  public let percentCompleted: Double
  public let duration: Double
  /// `DownloadState`-equivalent when the item has a remote copy to get
  /// (`downloaded` / `notDownloaded` / `downloading`); nil for local-only
  /// items, where no download action applies
  public let downloadState: String?
  /// True only when removing the local file keeps a copy to come back to —
  /// the same rule the phone's storage screen uses, evaluated phone-side
  /// so the watch never has to know why
  public let canOffload: Bool

  public var isFolder: Bool {
    type == SimpleItemType.folder.rawValue
  }

  public init(
    relativePath: String,
    title: String,
    details: String,
    type: Int16,
    isFinished: Bool,
    percentCompleted: Double,
    duration: Double,
    downloadState: String?,
    canOffload: Bool
  ) {
    self.relativePath = relativePath
    self.title = title
    self.details = details
    self.type = type
    self.isFinished = isFinished
    self.percentCompleted = percentCompleted
    self.duration = duration
    self.downloadState = downloadState
    self.canOffload = canOffload
  }
}

/// One page of a folder's contents in a `requestLibrary` reply
public struct WatchLibraryPage: Codable {
  public let items: [WatchLibraryItem]
  /// More rows exist past this page — the watch offers "Show more"
  public let hasMore: Bool

  public init(items: [WatchLibraryItem], hasMore: Bool) {
    self.items = items
    self.hasMore = hasMore
  }
}

/// Acknowledgement for `downloadItem` / `removeDownloadItem`. `error` is a
/// code (`notFound`, `noRemoteCopy`, `uploadInProgress`, `failed`), never a
/// user-facing sentence — the watch localizes its own copy.
public struct WatchActionResponse: Codable {
  public let ok: Bool
  public let error: String?

  public init(ok: Bool, error: String? = nil) {
    self.ok = ok
    self.error = error
  }
}
