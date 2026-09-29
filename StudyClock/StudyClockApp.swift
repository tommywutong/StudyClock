//
//  StudyClockApp.swift
//  StudyClock
//
//  Created by 吴桐 on 2026/9/27.
//

import SwiftUI

@main
struct StudyClockApp: App {
    @State private var viewModel = TimerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .task { viewModel.reload() }
        }

        #if os(macOS)
        MenuBarExtra("钟", systemImage: "timer") {
            MenuBarView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
