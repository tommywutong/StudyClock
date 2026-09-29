//
//  StudyClockUITests.swift
//  StudyClockUITests
//
//  Created by 吴桐 on 2026/9/27.
//

import XCTest

final class StudyClockUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testHistoryCanBeClosed() throws {
        let app = XCUIApplication()
        app.launch()

        let historyButton = app.buttons["查看学习历史"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()

        let closeButton = app.buttons["关闭学习历史"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()

        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
