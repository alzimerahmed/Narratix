//
//  StorageItem.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 21/8/21.
//  Copyright © 2021 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation

struct StorageItem: Identifiable {
  let id = UUID().uuidString
  let title: String
  let fileURL: URL
  let path: String
  let size: Int64
  let showWarning: Bool
  /// State of the library item this file belongs to, when there is one —
  /// powers the row's "Backed up"/"Downloading" caption
  let downloadState: DownloadState?
  /// The file has somewhere to come back from — it was uploaded to the cloud
  /// or the item streams from a media server — so deleting it is offloading,
  /// not data loss
  let canOffload: Bool

  var formattedSize: String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: ByteCountFormatter.CountStyle.file)
  }

  /// The caption under the file name; nil when there's nothing to say (a
  /// local-only book, or a file with no library record — the warning covers it)
  var stateLabel: String? {
    guard !showWarning else { return nil }
    switch downloadState {
    case .downloading:
      return "storage_state_downloading".localized
    case .downloaded where canOffload:
      return "storage_state_backed_up".localized
    case .notDownloaded:
      return "storage_state_in_cloud".localized
    default:
      return nil
    }
  }

  init(
    title: String,
    fileURL: URL,
    path: String,
    size: Int64,
    showWarning: Bool,
    downloadState: DownloadState? = nil,
    canOffload: Bool = false
  ) {
    self.title = title
    self.fileURL = fileURL
    self.path = path
    self.size = size
    self.showWarning = showWarning
    self.downloadState = downloadState
    self.canOffload = canOffload
  }
}
