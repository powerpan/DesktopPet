//
// PersonaTabView.swift
// 智能体设置 ·「人格」Tab。
//

import SwiftUI

struct PersonaTabView: View {
    @EnvironmentObject private var settings: AgentSettingsStore
    @EnvironmentObject private var petMenuSettings: SettingsViewModel

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 200)
            } header: {
                Text("系统提示（人格）")
            } footer: {
                MarkdownInlineText(source: AgentSettingsUICopy.personaFooter(testing: petMenuSettings.testingModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}
