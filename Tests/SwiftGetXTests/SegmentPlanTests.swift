import Testing
@testable import SwiftGetX

@Suite("SegmentPlan")
struct SegmentPlanTests {
    @Test("splits bytes into contiguous ranges")
    func splitsContiguousRanges() {
        let plan = SegmentPlan.make(totalBytes: 10, segmentCount: 3)

        #expect(plan.segments == [
            DownloadSegment(index: 0, start: 0, end: 3),
            DownloadSegment(index: 1, start: 4, end: 6),
            DownloadSegment(index: 2, start: 7, end: 9)
        ])
        #expect(plan.segments.reduce(Int64(0)) { $0 + $1.length } == 10)
    }

    @Test("does not create more segments than bytes")
    func capsSegmentsToByteCount() {
        let plan = SegmentPlan.make(totalBytes: 3, segmentCount: 8)

        #expect(plan.segments == [
            DownloadSegment(index: 0, start: 0, end: 0),
            DownloadSegment(index: 1, start: 1, end: 1),
            DownloadSegment(index: 2, start: 2, end: 2)
        ])
    }

    @Test("honors minimum split size")
    func honorsMinimumSplitSize() {
        let plan = SegmentPlan.make(totalBytes: 10, segmentCount: 8, minSplitSize: 4)

        #expect(plan.segments == [
            DownloadSegment(index: 0, start: 0, end: 4),
            DownloadSegment(index: 1, start: 5, end: 9)
        ])
    }

    @Test("keeps small files single segment")
    func keepsSmallFilesSingleSegment() {
        let plan = SegmentPlan.make(totalBytes: 1024, segmentCount: 8, minSplitSize: 1024 * 1024)

        #expect(plan.segments == [
            DownloadSegment(index: 0, start: 0, end: 1023)
        ])
    }

    @Test("progress sample calculates speed from deltas")
    func progressSampleCalculatesSpeed() async {
        let progress = SegmentProgress(initialBytes: 10)
        await progress.add(90)
        let sample = await progress.sample()

        #expect(sample.downloadedBytes == 100)
        #expect(sample.speedBytesPerSecond >= 0)
    }
}
