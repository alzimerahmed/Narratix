//
//  ListeningQueueItem+CoreDataProperties.swift
//  BookPlayerKit
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import CoreData
import Foundation

extension ListeningQueueItem {
  @nonobjc public class func fetchRequest() -> NSFetchRequest<ListeningQueueItem> {
    return NSFetchRequest<ListeningQueueItem>(entityName: "ListeningQueueItem")
  }

  @nonobjc public class func create(in context: NSManagedObjectContext) -> ListeningQueueItem {
    // swiftlint:disable force_cast
    return NSEntityDescription.insertNewObject(forEntityName: "ListeningQueueItem", into: context) as! ListeningQueueItem
    // swiftlint:enable force_cast
  }

  /// When the item entered the queue
  @NSManaged public var addedAt: Date
  /// Position in the queue; rewritten contiguously (0…n-1) on every add/remove/move
  @NSManaged public var order: Int16
  @NSManaged public var item: LibraryItem?
}
