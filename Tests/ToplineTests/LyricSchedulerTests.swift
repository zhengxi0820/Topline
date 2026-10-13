import Testing
@testable import Topline

struct LyricSchedulerTests {
    let lines = [
        LyricLine(time: 10, text: "A"),
        LyricLine(time: 20, text: "B"),
        LyricLine(time: 30, text: "C"),
    ]

    @Test func beforeFirstLine() {
        #expect(LyricScheduler.currentIndex(in: lines, at: 5) == nil)
        #expect(LyricScheduler.currentIndex(in: lines, at: 9.999) == nil)
    }

    @Test func exactBoundary() {
        #expect(LyricScheduler.currentIndex(in: lines, at: 10) == 0)
        #expect(LyricScheduler.currentIndex(in: lines, at: 20) == 1)
    }

    @Test func betweenLines() {
        #expect(LyricScheduler.currentIndex(in: lines, at: 15.7) == 0)
        #expect(LyricScheduler.currentIndex(in: lines, at: 29.9) == 1)
    }

    @Test func afterLastLine() {
        #expect(LyricScheduler.currentIndex(in: lines, at: 100) == 2)
    }

    @Test func emptyLyrics() {
        #expect(LyricScheduler.currentIndex(in: [], at: 10) == nil)
    }
}
