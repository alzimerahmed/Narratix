//
//  ItemCollection+CoreDataClass.swift
//  BookPlayerKit
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import CoreData
import Foundation

/// A user-made shelf: cross-cutting grouping where an item can belong to many
/// collections (unlike `Folder`, where an item has exactly one parent).
/// Local-only — never synced.
@objc(ItemCollection)
public class ItemCollection: NSManagedObject {
  public override func awakeFromInsert() {
    super.awakeFromInsert()
    setPrimitiveValue(Date(), forKey: "createdAt")
  }
}
