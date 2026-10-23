//
//  LibraryItem+CoreDataProperties.swift
//  BookPlayerKit
//
//  Created by Gianni Carlo on 4/23/19.
//  Copyright © 2019 BookPlayer LLC. All rights reserved.
//
//

import CoreData
import Foundation

extension LibraryItem {
  @nonobjc public class func fetchRequest() -> NSFetchRequest<LibraryItem> {
    return NSFetchRequest<LibraryItem>(entityName: "LibraryItem")
  }

  @NSManaged public var uuid: String
  @NSManaged public var currentTime: Double
  @NSManaged public var duration: Double
  @NSManaged public var title: String!
  @NSManaged public var percentCompleted: Double
  @NSManaged public var speed: Float
  @NSManaged public var library: Library?
  @NSManaged public var folder: Folder?
  @NSManaged public var isFinished: Bool
  @NSManaged public var lastPlayDate: Date?
  @NSManaged public var relativePath: String!
  @NSManaged public var remoteURL: URL?
  @NSManaged public var artworkURL: URL?
  @NSManaged public var originalFileName: String!
  @NSManaged public var orderRank: Int16
  @NSManaged public var bookmarks: NSSet?
  @NSManaged public var lastPlayed: Library?
  @NSManaged public var details: String!
  @NSManaged public var type: ItemType
  @NSManaged public var hardcoverBook: HardcoverBook?
  @NSManaged public var externalResources: NSSet?
  /// User-marked "did not finish" — distinct from `isFinished`, and independent
  /// of progress: an abandoned book keeps its position. Reads false on pre-v13 rows.
  @NSManaged public var didNotFinish: Bool
  /// Free-form note about the item (book-level memo, unlike the time-anchored
  /// `Bookmark.note`)
  @NSManaged public var note: String?
  /// Series the item belongs to (ingested from tags or set in item details).
  /// Local-only — never synced.
  @NSManaged public var seriesName: String?
  /// Book number inside `seriesName`; fractional entries (novellas) are
  /// supported. nil = unordered/unknown.
  @NSManaged public var seriesOrder: NSNumber?
  @NSManaged public var playbackSessions: NSSet?
  @NSManaged public var listeningQueueItems: NSSet?
  /// User-made shelves the item belongs to (many-to-many, local-only)
  @NSManaged public var collections: NSSet?
}

// MARK: Generated accessors for playbackSessions
extension LibraryItem {
  @objc(addPlaybackSessionsObject:)
  @NSManaged public func addToPlaybackSessions(_ value: PlaybackSession)

  @objc(removePlaybackSessionsObject:)
  @NSManaged public func removeFromPlaybackSessions(_ value: PlaybackSession)

  @objc(addPlaybackSessions:)
  @NSManaged public func addToPlaybackSessions(_ values: NSSet)

  @objc(removePlaybackSessions:)
  @NSManaged public func removeFromPlaybackSessions(_ values: NSSet)

  public var sessionsArray: [PlaybackSession] {
    return playbackSessions?.allObjects as? [PlaybackSession] ?? []
  }
}

// MARK: Generated accessors for listeningQueueItems
extension LibraryItem {
  @objc(addListeningQueueItemsObject:)
  @NSManaged public func addToListeningQueueItems(_ value: ListeningQueueItem)

  @objc(removeListeningQueueItemsObject:)
  @NSManaged public func removeFromListeningQueueItems(_ value: ListeningQueueItem)

  @objc(addListeningQueueItems:)
  @NSManaged public func addToListeningQueueItems(_ values: NSSet)

  @objc(removeListeningQueueItems:)
  @NSManaged public func removeFromListeningQueueItems(_ values: NSSet)

  public var queueItemsArray: [ListeningQueueItem] {
    return listeningQueueItems?.allObjects as? [ListeningQueueItem] ?? []
  }
}

// MARK: Generated accessors for externalResources
extension LibraryItem {
  @objc(addExternalResourcesObject:)
  @NSManaged public func addToExternalResources(_ value: ExternalResource)

  @objc(removeExternalResourcesObject:)
  @NSManaged public func removeFromExternalResources(_ value: ExternalResource)

  @objc(addExternalResources:)
  @NSManaged public func addToExternalResources(_ values: NSSet)

  @objc(removeExternalResources:)
  @NSManaged public func removeFromExternalResources(_ values: NSSet)
  
  public var resourcesArray: [ExternalResource] {
    return externalResources?.allObjects as? [ExternalResource] ?? []
  }
}

// MARK: Generated accessors for bookmarks

extension LibraryItem {
  @objc(addBookmarksObject:)
  @NSManaged public func addToBookmarks(_ value: Bookmark)

  @objc(removeBookmarksObject:)
  @NSManaged public func removeFromBookmarks(_ value: Bookmark)

  @objc(addBookmarks:)
  @NSManaged public func addToBookmarks(_ values: NSSet)

  @objc(removeBookmarks:)
  @NSManaged public func removeFromBookmarks(_ values: NSSet)
}

// MARK: Generated accessors for collections
extension LibraryItem {
  @objc(addCollectionsObject:)
  @NSManaged public func addToCollections(_ value: ItemCollection)

  @objc(removeCollectionsObject:)
  @NSManaged public func removeFromCollections(_ value: ItemCollection)

  @objc(addCollections:)
  @NSManaged public func addToCollections(_ values: NSSet)

  @objc(removeCollections:)
  @NSManaged public func removeFromCollections(_ values: NSSet)

  public var collectionsArray: [ItemCollection] {
    return collections?.allObjects as? [ItemCollection] ?? []
  }
}
