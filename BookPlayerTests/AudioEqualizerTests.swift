//
//  AudioEqualizerTests.swift
//  BookPlayerTests
//
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//  Narratix — Phase 3e (equalizer / voice boost).
//

import XCTest
@testable import BookPlayer
@testable import BookPlayerKit

/// Value-type coverage for the EQ half that needs no audio hardware: preset →
/// band expansion, biquad coefficient derivation, preamp headroom, settings
/// persistence. The tap callbacks themselves can't be exercised without a
/// render pipeline — covered by review, verified on device.
class AudioEqualizerTests: XCTestCase {
  override func setUp() {
    UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.equalizerPreset)
    UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.voiceBoostEnabled)
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.equalizerPreset)
    UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.voiceBoostEnabled)
  }

  func testOffAndFlatProduceNoBands() {
    XCTAssertTrue(EQPreset.off.bands.isEmpty)
    XCTAssertTrue(EQPreset.flat.bands.isEmpty)
  }

  func testProcessingPresetsProduceBands() {
    for preset in [EQPreset.voice, .bassBoost, .treble] {
      XCTAssertFalse(preset.bands.isEmpty, "\(preset) should define bands")
    }
  }

  func testEffectiveBandsRespectsVoiceBoost() {
    AudioEQSettings.preset = .flat
    AudioEQSettings.voiceBoostEnabled = false
    XCTAssertTrue(AudioEQSettings.effectiveBands.isEmpty)

    AudioEQSettings.voiceBoostEnabled = true
    XCTAssertEqual(
      AudioEQSettings.effectiveBands.count,
      AudioEQSettings.voiceBoostBands.count
    )
  }

  func testEffectiveBandsCappedAtMax() {
    AudioEQSettings.preset = .voice
    AudioEQSettings.voiceBoostEnabled = true
    XCTAssertLessThanOrEqual(
      AudioEQSettings.effectiveBands.count,
      AudioEQSettings.maxBands
    )
  }

  /// A 0 dB peaking section collapses to numerator == denominator — a true
  /// pass-through, which is what makes `.flat` a safe no-op EQ.
  func testZeroGainPeakingIsIdentity() {
    let coefficients = EQBiquad.coefficients(
      for: EQBandSpec(kind: .peaking, frequency: 1000, gainDb: 0, q: 1.0),
      sampleRate: 44100
    )
    XCTAssertEqual(coefficients.b0, 1, accuracy: 0.0001)
    XCTAssertEqual(coefficients.b1, coefficients.a1, accuracy: 0.0001)
    XCTAssertEqual(coefficients.b2, coefficients.a2, accuracy: 0.0001)
  }

  func testShelfZeroGainIsIdentity() {
    for kind in [EQBandKind.lowShelf, .highShelf] {
      let coefficients = EQBiquad.coefficients(
        for: EQBandSpec(kind: kind, frequency: 200, gainDb: 0, q: 0.707),
        sampleRate: 44100
      )
      XCTAssertEqual(coefficients.b0, 1, accuracy: 0.0001)
      XCTAssertEqual(coefficients.b1, coefficients.a1, accuracy: 0.0001)
      XCTAssertEqual(coefficients.b2, coefficients.a2, accuracy: 0.0001)
    }
  }

  func testBoostedBandLiftsItsRegion() {
    // +4 dB peaking at 3 kHz must produce b0 > 1 (direct-path gain above unity)
    let coefficients = EQBiquad.coefficients(
      for: EQBandSpec(kind: .peaking, frequency: 3000, gainDb: 4, q: 1.0),
      sampleRate: 44100
    )
    XCTAssertGreaterThan(coefficients.b0, 1)
  }

  func testOutOfRangeFrequencyIsClamped() {
    let coefficients = EQBiquad.coefficients(
      for: EQBandSpec(kind: .peaking, frequency: 1_000_000, gainDb: 6, q: 1.0),
      sampleRate: 44100
    )
    for value in [coefficients.b0, coefficients.b1, coefficients.b2, coefficients.a1, coefficients.a2] {
      XCTAssertTrue(value.isFinite)
    }
  }

  func testPreampNeverBoosts() {
    // No bands or small boosts keep unity gain
    XCTAssertEqual(AudioEQSettings.preamp(for: []), 1)

    // Voice's +4 dB peak exceeds the 3 dB headroom → pulls down below unity
    XCTAssertLessThan(AudioEQSettings.preamp(for: EQPreset.voice.bands), 1)

    let hotBands = [EQBandSpec(kind: .peaking, frequency: 1000, gainDb: 9, q: 1)]
    let hotPreamp = AudioEQSettings.preamp(for: hotBands)
    XCTAssertLessThan(hotPreamp, 1)
    // Capped at −6 dB → ≥ 0.5 linear
    XCTAssertGreaterThanOrEqual(hotPreamp, 0.5)
  }

  func testSettingsPersistence() {
    XCTAssertEqual(AudioEQSettings.preset, .off)
    AudioEQSettings.preset = .voice
    XCTAssertEqual(AudioEQSettings.preset, .voice)
    AudioEQSettings.preset = .off
    XCTAssertEqual(AudioEQSettings.preset, .off)

    XCTAssertFalse(AudioEQSettings.voiceBoostEnabled)
    AudioEQSettings.voiceBoostEnabled = true
    XCTAssertTrue(AudioEQSettings.voiceBoostEnabled)
  }
}
