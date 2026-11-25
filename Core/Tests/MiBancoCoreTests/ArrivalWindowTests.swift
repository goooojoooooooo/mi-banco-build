import Foundation
import Testing
@testable import MiBancoCore

private let announced = Date(timeIntervalSince1970: 1_795_000_000)

@Suite struct ArrivalWindowTests {
    @Test func landsWhileTheModelPublishes() {
        #expect(ArrivalWindow.isOpen(announcedAt: announced, now: announced.addingTimeInterval(0.56)))
    }

    /// Una llegada cuyo movimiento no apareció a tiempo no aterriza con un cambio posterior del libro.
    @Test func staleArrivalNeverLandsLater() {
        #expect(!ArrivalWindow.isOpen(announcedAt: announced, now: announced.addingTimeInterval(2)))
        #expect(!ArrivalWindow.isOpen(announcedAt: announced, now: announced.addingTimeInterval(180)))
    }

    @Test func slowMotionStretchesTheWindow() {
        #expect(ArrivalWindow.isOpen(announcedAt: announced, now: announced.addingTimeInterval(6), timeMultiplier: 4))
        #expect(!ArrivalWindow.isOpen(announcedAt: announced, now: announced.addingTimeInterval(8), timeMultiplier: 4))
    }

    @Test func clockGoingBackwardsDoesNotLand() {
        #expect(!ArrivalWindow.isOpen(announcedAt: announced, now: announced.addingTimeInterval(-1)))
    }
}
