import Foundation
import Testing
@testable import PaddockCore

@Suite("App version")
struct AppVersionTests {
    @Test func versionedBuild() {
        let version = AppVersion(info: [
            "CFBundleShortVersionString": "261106.2",
            "CFBundleVersion": "412",
            "PaddockCommit": "81f2c45"
        ])
        #expect(version.version == "261106.2")
        #expect(version.build == "412")
        #expect(version.commit == "81f2c45")
        #expect(!version.isDirty)
        #expect(version.label == "261106.2")
        #expect(version.help == "Paddock 261106.2, commit 81f2c45 (build 412)")
    }

    @Test func dirtyBuildSaysSo() {
        let version = AppVersion(info: [
            "CFBundleShortVersionString": "261106.0",
            "CFBundleVersion": "7",
            "PaddockCommit": "abc1234-dirty"
        ])
        #expect(version.commit == "abc1234")
        #expect(version.isDirty)
        #expect(version.help == "Paddock 261106.0, commit abc1234 (build 7)\nBuilt with uncommitted changes")
    }

    @Test func placeholdersAreUnversioned() {
        let version = AppVersion(info: [
            "CFBundleShortVersionString": "0.0",
            "CFBundleVersion": "0",
            "PaddockCommit": ""
        ])
        #expect(version.version == nil)
        #expect(version.build == nil)
        #expect(version.commit == nil)
        #expect(version.label == "unversioned")
        #expect(version.help.hasPrefix("Unversioned build"))
    }

    @Test func missingKeysAreUnversioned() {
        let version = AppVersion(info: [:])
        #expect(version == AppVersion(info: ["CFBundleShortVersionString": 3]))
        #expect(version.label == "unversioned")
    }
}
