//
//  WeekendPlannerIOSUITests.swift
//  WeekendPlannerIOSUITests
//
//  Created by Mazhar-Elstub on 07/02/2026.
//

import XCTest

final class WeekendPlannerIOSUITests: XCTestCase {

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
    func testExample() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitest-skip-auth-splash")
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Dashboard"].exists)
        XCTAssertTrue(tabBar.buttons["Planner"].exists)
        XCTAssertTrue(tabBar.buttons["Settings"].exists)
        XCTAssertFalse(app.otherElements["onboarding.carousel"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testResumePerformance() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitest-skip-auth-splash")
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        measure(metrics: [XCTClockMetric()]) {
            app.activate()
            XCTAssertTrue(tabBar.waitForExistence(timeout: 2))
        }
    }

    @MainActor
    func testCoreInteractionPerformanceSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitest-skip-auth-splash")
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        measure(metrics: [XCTClockMetric()]) {
            tabBar.buttons["Planner"].tap()
            tabBar.buttons["Dashboard"].tap()
            tabBar.buttons["Settings"].tap()
        }
    }

    @MainActor
    func testAccountScreenShowsDeleteAccountAction() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitest-skip-auth-splash")
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Settings"].tap()

        let accountRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Account")).firstMatch
        XCTAssertTrue(accountRow.waitForExistence(timeout: 5))
        accountRow.tap()

        let deleteButton = app.buttons["Delete account"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testRootTabsShareSameHorizontalCardEdgesAsSettings() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitest-skip-auth-splash")
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons["Dashboard"].tap()
        let dashboardLegend = firstElement(in: app, withIdentifier: "dashboard.legend.container")
        XCTAssertTrue(dashboardLegend.waitForExistence(timeout: 5))

        tabBar.buttons["Planner"].tap()
        let plannerMonthSelector = firstElement(in: app, withIdentifier: "planner.monthSelector.container")
        XCTAssertTrue(plannerMonthSelector.waitForExistence(timeout: 5))
        let plannerWeekendCard = firstElement(in: app, matchingIdentifierPrefix: "planner.weekend.card.")
        XCTAssertTrue(plannerWeekendCard.waitForExistence(timeout: 5))

        let dashboardMinX = Double(dashboardLegend.frame.minX)
        let dashboardMaxX = Double(dashboardLegend.frame.maxX)
        let plannerSelectorMinX = Double(plannerMonthSelector.frame.minX)
        let plannerSelectorMaxX = Double(plannerMonthSelector.frame.maxX)
        let plannerWeekendCardMinX = Double(plannerWeekendCard.frame.minX)
        let plannerWeekendCardMaxX = Double(plannerWeekendCard.frame.maxX)

        tabBar.buttons["Settings"].tap()
        let settingsAccount = firstElement(in: app, withIdentifier: "settings.account.container")
        XCTAssertTrue(settingsAccount.waitForExistence(timeout: 5))
        let settingsMinX = Double(settingsAccount.frame.minX)
        let settingsMaxX = Double(settingsAccount.frame.maxX)

        let tolerance = 1.0

        XCTAssertEqual(
            dashboardMinX,
            settingsMinX,
            accuracy: tolerance
        )
        XCTAssertEqual(
            dashboardMaxX,
            settingsMaxX,
            accuracy: tolerance
        )
        XCTAssertEqual(
            plannerSelectorMinX,
            settingsMinX,
            accuracy: tolerance
        )
        XCTAssertEqual(
            plannerSelectorMaxX,
            settingsMaxX,
            accuracy: tolerance
        )
        XCTAssertEqual(
            plannerWeekendCardMinX,
            settingsMinX,
            accuracy: tolerance
        )
        XCTAssertEqual(
            plannerWeekendCardMaxX,
            settingsMaxX,
            accuracy: tolerance
        )
    }

    @MainActor
    func testOnboardingFlowAndChecklistActionsAppear() throws {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--uitest-skip-auth-splash", "--uitest-show-onboarding"])
        app.launch()

        let firstSkipButton = app.buttons["onboarding.skip"]
        XCTAssertTrue(firstSkipButton.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Plan weekends and holidays with clarity."].waitForExistence(timeout: 10))

        let nextButton = app.buttons["onboarding.next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
        nextButton.tap()
        XCTAssertTrue(app.staticTexts["Shape your Life Schedule."].waitForExistence(timeout: 3))

        XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
        nextButton.tap()
        XCTAssertTrue(app.staticTexts["Plan better together."].waitForExistence(timeout: 3))

        let getStartedButton = app.buttons["onboarding.get-started"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 3))
        getStartedButton.tap()

        let checklist = app.otherElements["onboarding.checklist"]
        XCTAssertTrue(checklist.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["onboarding.checklist.life-schedule"].exists)
        XCTAssertTrue(app.otherElements["onboarding.checklist.sharing"].exists)
        XCTAssertTrue(app.otherElements["onboarding.checklist.add-plan"].exists)

        let continueButton = app.buttons["onboarding.checklist.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        continueButton.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))

        app.terminate()

        let skipApp = XCUIApplication()
        skipApp.launchArguments.append(contentsOf: ["--uitest-skip-auth-splash", "--uitest-show-onboarding"])
        skipApp.launch()
        XCTAssertTrue(skipApp.buttons["onboarding.skip"].waitForExistence(timeout: 15))
        let skipButton = skipApp.buttons["onboarding.skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 3))
        skipButton.tap()
        XCTAssertTrue(skipApp.otherElements["onboarding.checklist"].waitForExistence(timeout: 5))
    }

    private func firstElement(in app: XCUIApplication, withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func firstElement(in app: XCUIApplication, matchingIdentifierPrefix prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .firstMatch
    }
}
