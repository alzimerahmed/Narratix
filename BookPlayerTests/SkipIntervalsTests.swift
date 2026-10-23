//
//  SkipIntervalsTests.swift
//  BookPlayerTests
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import XCTest

@testable import Narratix

/// The custom skip-interval field's parser: lenient input (comma decimals, whitespace),
/// out-of-range numbers clamped to the field's 1 s–1 h range, blanks and non-numbers
/// rejected so the current interval keeps its value
final class SkipIntervalsTests: XCTestCase {
  func testParseSeconds_acceptsPlainAndCommaDecimals() {
    XCTAssertEqual(SkipIntervalsSectionView.parseSeconds("42"), 42)
    XCTAssertEqual(SkipIntervalsSectionView.parseSeconds("1,5"), 1.5)
    XCTAssertEqual(SkipIntervalsSectionView.parseSeconds("  90  "), 90)
  }

  func testParseSeconds_clampsToTheCustomRange() {
    XCTAssertEqual(
      SkipIntervalsSectionView.parseSeconds("0"),
      SkipIntervalsSectionView.customIntervalRange.lowerBound
    )
    XCTAssertEqual(
      SkipIntervalsSectionView.parseSeconds("-5"),
      SkipIntervalsSectionView.customIntervalRange.lowerBound
    )
    XCTAssertEqual(
      SkipIntervalsSectionView.parseSeconds("9999"),
      SkipIntervalsSectionView.customIntervalRange.upperBound
    )
  }

  func testParseSeconds_rejectsBlankAndNonNumeric() {
    XCTAssertNil(SkipIntervalsSectionView.parseSeconds(""))
    XCTAssertNil(SkipIntervalsSectionView.parseSeconds("   "))
    XCTAssertNil(SkipIntervalsSectionView.parseSeconds("abc"))
  }
}
