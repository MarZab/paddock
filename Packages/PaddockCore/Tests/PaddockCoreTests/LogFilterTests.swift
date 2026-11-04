import Foundation
import Testing
@testable import PaddockCore

@Suite("Log filter")
struct LogFilterTests {
    let entries = [
        LogEntry(category: .build, source: "app", message: "#5 [2/4] RUN apt-get install -y ripgrep"),
        LogEntry(category: .paddock, message: "Could not start app: sbx is not installed", isError: true),
        LogEntry(category: .sandbox, source: "paddock-app", message: "Reached api.github.com:443"),
        LogEntry(category: .voice, source: "paddock-app · agent 2", message: "Could not listen: denied", isError: true)
    ]

    @Test func noneChosenShowsEverything() {
        #expect(LogFilter().apply(entries) == entries)
    }

    @Test func chosenCategoriesOnly() {
        var filter = LogFilter()
        filter.toggle(.build)
        #expect(filter.apply(entries).map(\.category) == [.build])
        filter.toggle(.voice)
        #expect(filter.apply(entries).map(\.category) == [.build, .voice])
        filter.toggle(.build)
        filter.toggle(.voice)
        #expect(filter.categories.isEmpty)
        #expect(filter.apply(entries) == entries)
    }

    @Test func errorsOnly() {
        #expect(LogFilter(errorsOnly: true).apply(entries).map(\.category) == [.paddock, .voice])
        #expect(LogFilter(categories: [.paddock], errorsOnly: true).apply(entries).map(\.category) == [.paddock])
    }

    @Test func textMatchesMessageOrSourceAnyCase() {
        #expect(LogFilter(text: "  GITHUB ").apply(entries).map(\.category) == [.sandbox])
        #expect(LogFilter(text: "could not").apply(entries).count == 2)
        #expect(LogFilter(categories: [.voice], text: "could not").apply(entries).map(\.category) == [.voice])
        #expect(LogFilter(text: "agent 2").apply(entries).map(\.category) == [.voice])
        #expect(LogFilter(text: "paddock-app").apply(entries).map(\.category) == [.sandbox, .voice])
    }

    @Test func chosenCategoriesAreStoredByName() {
        let filter = LogFilter(categories: [.voice, .build])
        #expect(filter.categoriesStored == "build,voice")
        #expect(LogFilter.categories(stored: filter.categoriesStored) == [.build, .voice])
        // a category a later version added (or a typo) is ignored
        #expect(LogFilter.categories(stored: "build,future,") == [.build])
        #expect(LogFilter.categories(stored: "").isEmpty)
    }

    @Test func theFileLineNamesTheCategoryAndSource() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(LogEntry(date: date, category: .build, message: "done").fileLine == "1970-01-01T00:00:00Z [build] - done")
        #expect(LogEntry(date: date, category: .voice, source: "app · agent", message: "no mic", isError: true).fileLine
            == "1970-01-01T00:00:00Z ERROR [voice] app · agent: no mic")
    }

    @Test(arguments: [
        LogEntry(date: Date(timeIntervalSince1970: 1_800_000_000), category: .build, message: "Step 3: RUN [x] a: b"),
        LogEntry(date: Date(timeIntervalSince1970: 1), category: .sandbox, source: "app · agent 2", message: "a: b", isError: true),
        LogEntry(date: Date(timeIntervalSince1970: 2), category: .paddock, source: "app", message: ""),
        LogEntry(date: Date(timeIntervalSince1970: 3), category: .processes, message: "- leading dash"),
        LogEntry(date: Date(timeIntervalSince1970: 4), category: .voice, message: ""),
    ])
    func aFileLineReadsBack(entry: LogEntry) throws {
        let read = try #require(LogEntry(fileLine: entry.fileLine))
        #expect(read.date == entry.date && read.category == entry.category && read.source == entry.source
            && read.message == entry.message && read.isError == entry.isError)
    }

    @Test func aSourceWithAColonStaysOneSource() throws {
        let entry = LogEntry(date: Date(timeIntervalSince1970: 0), category: .sandbox, source: "odd: name", message: "m")
        #expect(try #require(LogEntry(fileLine: entry.fileLine)).source == "odd:name")
    }

    @Test func linesFromBeforeAndOddLinesStillShow() {
        let text = """
            1970-01-01T00:00:00Z [build] done
            1970-01-01T00:00:01Z ERROR [voice] app · agent: no mic
            not a log line
            1970-01-01T00:00:02Z [future] new category

            """
        let entries = LogFiles.entries(in: text)
        #expect(entries.map(\.message) == ["done", "no mic", "not a log line", "1970-01-01T00:00:02Z [future] new category"])
        #expect(entries[1].source == "app · agent" && entries[1].isError)
        #expect(entries[2].date == entries[1].date && entries[2].category == .paddock)
    }
}

@Suite("Log files")
struct LogFilesTests {
    let utc = TimeZone(identifier: "UTC") ?? .current

    @Test func sessionsAreListedNewestFirstWithoutTheCurrentOne() {
        let names = ["paddock-2026-11-04_13-00-00-12.log", "paddock.log", "notes.txt",
                     "paddock-2026-11-04_14-30-05-7.log", "paddock-2026-11-03_09-00-00-99.log"]
        let sessions = LogFiles.sessions(names, current: "paddock-2026-11-04_14-30-05-7.log", timeZone: utc)
        #expect(sessions.map(\.name) == ["paddock-2026-11-04_13-00-00-12.log", "paddock-2026-11-03_09-00-00-99.log"])
        #expect(sessions[0].pid == 12)
        #expect(sessions[0].started == Date(timeIntervalSince1970: 1_793_797_200))
        // the name Paddock writes reads back
        let name = LogFiles.name(started: Date(timeIntervalSince1970: 1_793_797_200), pid: 42, timeZone: utc)
        #expect(LogFiles.session(named: name, timeZone: utc)?.started == Date(timeIntervalSince1970: 1_793_797_200))
    }

    @Test func namedByStartAndProcess() {
        let started = Date(timeIntervalSince1970: 1_793_348_750)  // 2026-10-30 08:25:50 UTC
        let name = LogFiles.name(started: started, pid: 4711, timeZone: utc)
        #expect(name == "paddock-2026-10-30_08-25-50-4711.log")
        #expect(LogFiles.isPaddockLog(name))
        #expect(LogFiles.isPaddockLog("paddock.log"))
        #expect(!LogFiles.isPaddockLog("paddock-2026-10-30_08-25-50-4711.log.bak"))
        #expect(!LogFiles.isPaddockLog("notes.txt"))
    }

    @Test func filesOlderThanAWeekGoTheCurrentStays() {
        let now = Date(timeIntervalSince1970: 1_793_348_750)
        let day: TimeInterval = 24 * 60 * 60
        let current = "paddock-2026-10-01_10-00-00-1.log"  // a long session: started long ago, written now
        let files: [(name: String, modified: Date)] = [
            ("paddock-2026-10-20_10-00-00-1.log", now - 10 * day),
            ("paddock-2026-10-25_10-00-00-1.log", now - 5 * day),
            ("paddock.log", now - 8 * day),
            ("notes.txt", now - 30 * day),
            (current, now - 30 * day)
        ]
        #expect(LogFiles.toRemove(files, current: current, now: now)
            == ["paddock-2026-10-20_10-00-00-1.log", "paddock.log"])
    }
}
