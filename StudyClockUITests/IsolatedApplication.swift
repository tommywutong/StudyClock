import XCTest

extension StudyClockUITests {
    @MainActor
    func makeIsolatedApplication() throws -> XCUIApplication {
        #if os(macOS)
        var runner = Bundle(for: StudyClockUITests.self).bundleURL
        while runner.pathExtension != "app", runner.path != "/" {
            runner.deleteLastPathComponent()
        }
        let products = runner.deletingLastPathComponent()
        let library = products.appendingPathComponent("StudyClock.app/Contents/MacOS/StudyClock.debug.dylib")
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyClockUIFixture-\(UUID())", isDirectory: true)
        let appURL = temporary.appendingPathComponent("StudyClockUIFixture.app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        let executable = contents.appendingPathComponent("MacOS/StudyClockUIFixture")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/FixtureApp.swift")
        do {
            try runFixtureTool("/usr/bin/xcrun", arguments: [
                "swiftc", "-parse-as-library", "-D", "STUDYCLOCK_UI_FIXTURE",
                "-I", products.path, library.path,
                "-Xlinker", "-rpath", "-Xlinker", library.deletingLastPathComponent().path,
                source.path, "-o", executable.path
            ])
            let info: [String: Any] = [
                "CFBundleExecutable": "StudyClockUIFixture",
                "CFBundleIdentifier": "com.tommywu.StudyClock.UIFixture.\(UUID().uuidString)",
                "CFBundleName": "StudyClockUIFixture",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1"
            ]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            try runFixtureTool("/usr/bin/codesign", arguments: ["--sign", "-", appURL.path])
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        let app = XCUIApplication(url: appURL)
        addTeardownBlock { @MainActor in
            app.terminate()
            try? FileManager.default.removeItem(at: temporary)
        }
        return app
        #else
        throw XCTSkip("离线 UI fixture 使用 macOS 的应用 URL 启动接口。")
        #endif
    }

    #if os(macOS)
    private func runFixtureTool(_ executable: String, arguments: [String]) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = errors
        try process.run()
        let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "StudyClockUIFixture", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: String(decoding: diagnostics, as: UTF8.self)
            ])
        }
    }
    #endif
}
