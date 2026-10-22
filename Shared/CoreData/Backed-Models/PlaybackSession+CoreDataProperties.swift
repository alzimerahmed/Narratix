//
//  PlaybackSession+CoreDataProperties.swift
//  BookPlayerKit
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import CoreData
import Foundation

extension PlaybackSession {
  @nonobjc public class func fetchRequest() -> NSFetchRequest<PlaybackSession> {
    return NSFetchRequest<PlaybackSession>(entityName: "PlaybackSession")
  }

  @nonobjc public class func create(in context: NSManagedObjectContext) -> PlaybackSession {
    // swiftlint:disable force_cast
    return NSEntityDescription.insertNewObject(forEntityName: "PlaybackSession", into: context) as! PlaybackSession
    // swiftlint:enable force_cast
  }

  /// When the listening session started
  @NSManaged public var date: Date
  /// Position in the item (book-time seconds) when the session was last persisted
  @NSManaged public var position: Double
  /// Seconds this session ran between its start and its last update
  @NSManaged public var duration: Double
  @NSManaged public var item: LibraryItem?
}
