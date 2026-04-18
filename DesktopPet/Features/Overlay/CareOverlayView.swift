//
// CareOverlayView.swift
// 饲养叠加层：心情、能量、今日陪伴、喂食与戳戳。
//

import SwiftUI

struct CareOverlayView: View {
    @EnvironmentObject private var care: PetCareModel
    @State private var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("七七猫 · 饲养")
                .font(.headline)
            moodBar(title: "心情", value: care.state.mood)
            moodBar(title: "能量", value: care.state.energy)
            Text("今日陪伴 \(care.state.todayCompanionSeconds / 60) 分钟")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("喂食") {
                    toast = care.feedIfAllowed() ? "喵～" : "还在冷却哦"
                }
                Button("戳戳") {
                    toast = care.petIfAllowed() ? "呼噜…" : "稍后再戳嘛"
                }
            }
            if let toast {
                Text(toast)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func moodBar(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: value)
        }
    }
}
