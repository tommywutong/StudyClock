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
    func testStatisticsPageOpensAndChangesPeriod() throws {
        let app = XCUIApplication()
        app.launch()

        let statisticsButton = app.buttons["查看学习统计"]
        XCTAssertTrue(statisticsButton.waitForExistence(timeout: 5))
        statisticsButton.tap()

        let period7Button = app.buttons["statistics-period-7"]
        XCTAssertTrue(period7Button.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["近 7 天"].waitForExistence(timeout: 5))

        let period15Button = app.buttons["statistics-period-15"]
        XCTAssertTrue(period15Button.waitForExistence(timeout: 5))
        period15Button.tap()
        XCTAssertTrue(app.staticTexts["近 15 天"].waitForExistence(timeout: 5))

        let period30Button = app.buttons["statistics-period-30"]
        XCTAssertTrue(period30Button.waitForExistence(timeout: 5))
        period30Button.tap()
        XCTAssertTrue(app.staticTexts["近 30 天"].waitForExistence(timeout: 5))

        let closeButton = app.buttons["关闭学习统计"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()
        XCTAssertTrue(statisticsButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testStatisticsPageOpensCalendarAndReturnsToStatistics() throws {
        let app = try makeIsolatedApplication()
        app.launch()

        let statisticsButton = app.buttons["查看学习统计"]
        XCTAssertTrue(statisticsButton.waitForExistence(timeout: 5))
        statisticsButton.tap()

        let calendarSection = app.buttons["statistics-section-calendar"]
        XCTAssertTrue(calendarSection.waitForExistence(timeout: 5))
        calendarSection.tap()
        XCTAssertTrue(app.staticTexts["学习日历"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "当前连续学习")
        ).firstMatch.waitForExistence(timeout: 5))

        let statisticsSection = app.buttons["statistics-section-statistics"]
        XCTAssertTrue(statisticsSection.waitForExistence(timeout: 5))
        statisticsSection.tap()
        XCTAssertTrue(app.buttons["statistics-period-7"].waitForExistence(timeout: 5))

        let closeButton = app.buttons["关闭学习统计"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()
        XCTAssertTrue(statisticsButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTaskManagementCanAddTask() throws {
        let app = try makeIsolatedApplication()
        app.launch()

        let managementButton = app.buttons["管理学习任务"]
        XCTAssertTrue(managementButton.waitForExistence(timeout: 5))
        managementButton.tap()
        let addButton = app.buttons["task-add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let saveButton = app.buttons["task-save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertFalse(saveButton.isEnabled)
        let nameField = app.textFields["task-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        let taskName = "英语听力 UI \(UUID().uuidString.prefix(8))"
        nameField.typeText(taskName)
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()
        XCTAssertTrue(app.staticTexts[taskName].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
