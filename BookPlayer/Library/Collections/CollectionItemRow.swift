//
//  CollectionItemRow.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import SwiftUI

/// The row shared by the collection detail and the series/author detail
/// lists: `BookView` for everything (folders play their next playable item on
/// select, so no `LibraryNode` push is needed inside the sheet), with a leading
/// book-number badge whenever the item carries series ordering.
struct CollectionItemRow: View {
  let item: SimpleLibraryItem
  let onSelect: () -> Void

  @EnvironmentObject private var theme: ThemeViewModel

  /// "3" for 3.0, "3.5" for a novella — never "3.0"
  private var bookNumber: String? {
    guard let order = item.seriesOrder else { return nil }
    return order == floor(order) ? String(Int(order)) : String(order)
  }

  var body: some View {
    HStack(spacing: Spacing.S2) {
      if let bookNumber {
        Text(verbatim: bookNumber)
          .bpFont(.caption)
          .foregroundStyle(theme.secondaryColor)
          .frame(minWidth: 24)
          .accessibilityLabel(
            Text(String(format: "series_order_accessibility_label".localized, bookNumber))
          )
      }
      BookView(item: item, artworkTap: onSelect)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      onSelect()
    }
    /// The row collapses to one element; its default action selects
    .accessibilityAction {
      onSelect()
    }
  }
}
