import SwiftUI

#if os(macOS)
struct MenuBarView: View {
    let viewModel: TimerViewModel

    var body: some View {
        TimerDashboardView(viewModel: viewModel)
            .frame(width: 380, height: 520)
    }
}
#endif
