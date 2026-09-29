//
//  ContentView.swift
//  StudyClock
//
//  Created by 吴桐 on 2026/9/27.
//

import SwiftUI

struct ContentView: View {
    let viewModel: TimerViewModel

    var body: some View {
        NavigationStack {
            TimerDashboardView(viewModel: viewModel)
        }
    }
}

#Preview {
    ContentView(viewModel: TimerViewModel())
}
