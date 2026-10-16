#if STUDYCLOCK_UI_FIXTURE
import SwiftUI
@testable import StudyClock

@main
struct StudyClockUIFixture: App {
    @State private var model = TimerViewModel(
        store: try! StudyStore.makeInMemory(), reloader: FixtureWidgetReloader())

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: model)
                .frame(minWidth: 620, minHeight: 560)
        }
    }
}

// The fixture exercises production views without reloading the user's real Widgets.
private struct FixtureWidgetReloader: StudyClockWidgetReloading {
    nonisolated func reloadTimelines() {}
}
#endif
