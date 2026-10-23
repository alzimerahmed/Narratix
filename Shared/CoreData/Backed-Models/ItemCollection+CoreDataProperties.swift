//
//  ItemCollection+CoreDataProperties.swift
//  BookPlayerKit
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import CoreData
import Foundation

extension ItemCollection {
  @nonobjc public class func fetchRequest() -> NSFetchRequest<ItemCollection> {
    return NSFetchRequest<ItemCollection>(entityName: "ItemCollection")
  }

  @nonobjc public class func create(in context: NSManagedObjectContext) -> ItemCollection {
    // swiftlint:disable force_cast
    return NSEntityDescription.insertNewObject(forEntityName: "ItemCollection", into: context) as! ItemCollection
    // swiftlint:enable force_cast
  }

  /// Stable identity — survives renames (collections have no path)
  @NSManaged public var uuid: String
  @NSManaged public var title: String
  /// When the collection was created (stamped on insert)
  @NSManaged public var createdAt: Date?
  /// Member items — many-to-many; deleting the collection nullifies members,
  /// deleting an item removes it from every collection
  @NSManaged public var items: NSSet?
}

// MARK: Generated accessors for items
extension ItemCollection {
  @objc(addItemsObject:)
  @NSManaged public func addToItems(_ value: LibraryItem)

  @objc(removeItemsObject:)
  @NSManaged public func removeFromItems(_ value: LibraryItem)

  @objc(addItems:)
  @NSManaged public func addToItems(_ values: NSSet)

  @objc(removeItems:)
  @NSManaged public func removeFromItems(_ values: NSSet)

  public var itemsArray: [LibraryItem] {
    return items?.allObjects as? [LibraryItem] ?? []
  }
}
