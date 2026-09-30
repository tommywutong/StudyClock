//
//  StudyClockApp.swift
//  StudyClock
//
//  Created by 吴桐 on 2026/9/27.
//

import SwiftUI

@main
struct StudyClockApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = TimerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .task { viewModel.reload() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    viewModel.refreshFromExternalStore()
                }
        }

        #if os(macOS)
        MenuBarExtra("钟", systemImage: "timer") {
            MenuBarView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
