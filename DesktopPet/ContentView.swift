//
// ContentView.swift
// 早期脚手架用的演示窗口视图；当前桌宠主界面由 PetWindow + PetContainerView 承担，本文件可保留给预览或后续主窗口。
//

import SwiftUI

struct ContentView: View {
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 24) {
            Text("DesktopPet")
                .font(.largeTitle.weight(.semibold))

            ZStack {
                Circle()
                    .fill(.linearGradient(
                        colors: [.mint.opacity(0.35), .blue.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 140, height: 140)

                Text("🐾")
                    .font(.system(size: 72))
                    .offset(y: bounce ? -6 : 6)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: bounce
                    )
            }

            Text("在 Xcode 中打开 `DesktopPet.xcodeproj`，运行即可启动窗口。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { bounce = true }
    }
}

#Preview {
    ContentView()
        .frame(width: 480, height: 360)
}
