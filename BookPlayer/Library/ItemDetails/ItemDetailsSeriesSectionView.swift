//
//  ItemDetailsSeriesSectionView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import SwiftUI

/// The series row of the item-details form: name + book number (fractional
/// numbers allowed for novellas — ".decimalPad" suggests the layout).
struct ItemDetailsSeriesSectionView: View {
  @Binding var name: String
  @Binding var order: String

  @EnvironmentObject private var theme: ThemeViewModel

  var body: some View {
    ThemedSection {
      ClearableTextField("series_name_placeholder".localized, text: $name)
      ClearableTextField("series_order_placeholder".localized, text: $order)
        .keyboardType(.decimalPad)
    } header: {
      Text("series_title")
        .foregroundStyle(theme.secondaryColor)
    }
    .listRowBackground(theme.secondarySystemBackgroundColor)
  }
}

#Preview {
  ItemDetailsSeriesSectionView(name: .constant("Mistborn"), order: .constant("2"))
    .environmentObject(ThemeViewModel())
}
