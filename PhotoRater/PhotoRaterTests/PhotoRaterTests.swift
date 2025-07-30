//
//  PhotoRaterTests.swift
//  PhotoRaterTests
//
//  Created by David Harms on 4/17/25.
//

import Testing
@testable import PhotoRater

struct PhotoRaterTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    /// Ensure that the `averageScore` property correctly computes the mean of
    /// the component scores.
    @Test func testDetailedScoresAverage() async throws {
        // Given a set of known detailed scores
        let scores = DetailedScores(
            overall: 0,
            visualQuality: 80,
            attractiveness: 70,
            datingAppeal: 90,
            swipeWorthiness: 60
        )

        // When computing the average
        let expectedAverage = 75.0

        // Then the calculated average should match our expectation
        #expect(scores.averageScore == expectedAverage)
    }

}
