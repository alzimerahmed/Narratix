//
//  LoadingOverlayState.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 24/7/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import SwiftUI

@Observable
class LoadingOverlayState {
  var show: Bool = false
  var message: String?
  var error: Error?

  /// `Binding<Error?>` for `.errorAlert(error:)` — `@Environment` no longer
  /// projects a Binding for `@Observable` types on the iOS 26 SDK, so call
  /// sites can't write `$loadingState.error` anymore (same pattern as
  /// `PlayerState.showPlayerBinding`)
  var errorBinding: Binding<Error?> {
    .init(
      get: { self.error },
      set: { self.error = $0 }
    )
  }

  init() {}
}
