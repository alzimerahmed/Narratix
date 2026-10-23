//
//  PlaybackSession+CoreDataClass.swift
//  BookPlayerKit
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import CoreData
import Foundation

@objc(PlaybackSession)
public class PlaybackSession: NSManagedObject {
  public override func awakeFromInsert() {
    super.awakeFromInsert()
    setPrimitiveValue(Date(), forKey: "date")
  }
}
