//
// SlackPetHelpCommand.swift
// Slack 入站：识别「帮助 / help」等并返回集成说明（文案随系统设置「启用测试」切换详略与语气）。
//

import Foundation

enum SlackPetHelpCommand {
    /// 与 `SettingsViewModel` 中 `testingModeUI` 一致，用于在未注入 Settings 时读取。
    private static let testingModeUserDefaultsKey = "DesktopPet.settings.testingModeUI"

    /// 用户仅询问用法时返回 true；避免把「帮我点一下屏幕」等误当帮助（不含远程点屏触发词）。
    static func isHelpRequest(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let lower = t.lowercased()

        if lower.hasPrefix("!pet help") { return restMeaningless(String(t.dropFirst("!pet help".count))) }
        if lower.hasPrefix("!pet 帮助") { return restMeaningless(String(t.dropFirst("!pet 帮助".count))) }

        if ["help", "usage", "commands"].contains(lower) { return true }

        let phrases = [
            "使用说明", "指令说明", "slack 帮助", "slack帮助", "怎么用", "怎麼用", "帮助一下", "帮助", "用法", "指令", "命令",
        ]
        for p in phrases {
            if matchesPhrasePrefix(t, phrase: p) { return true }
        }
        return false
    }

    /// 发回 Slack 的说明（`chat.postMessage` 使用 `markdown_text`，粗体写 `**…**`）。
    static func integrationHelpMarkdown() -> String {
        UserDefaults.standard.bool(forKey: testingModeUserDefaultsKey)
            ? integrationHelpMarkdownTesting
            : integrationHelpMarkdownUser
    }

    // MARK: - 日常（未开「启用测试」）：偏口语、只给中文触发示例，不出现 `!pet` 类英文口令

    private static let integrationHelpMarkdownUser: String = """
    🐱 **七七和 Slack 能帮你什么**

    **对话怎么同步**  
    在 Mac 上打开桌宠的「智能体工作台 → **连接**」：打开 Slack、填好 Bot 与**监控频道**，把频道**绑到一条本地会话**，需要的话再打开入站、出站。之后你在频道里发的文字、图片会进桌宠聊天，模型的回复也会回到 Slack，一般在**同一条讨论串**里接着聊。

    **想在 Slack 里再开一条新的本地会话**  
    这条需要桌宠能认出的**固定英文前缀**（避免大家日常聊天误触发）。**日常模式不在此写出那句英文**；请在本机 **系统设置 → DesktopPet** 打开 **「启用测试」**，再回到「连接」页的 Slack 说明里查看**可复制整句**和标题示例。

    **远程点屏（让七七帮你在 Mac 上点一下）**  
    在已经启用 Slack 的**监控频道**里，发一句以**中文**开头的话就行，例如 **「远程点屏，」**、**「远程点击，」**、**「帮点一下屏幕，」**、**「猫猫远程点屏，」**（**词后面请马上接逗号、句号或空格**，不要和后面的汉字粘在一起，比如别说成「远程点屏谢谢」）。七七会截一帧当前该截的屏幕（跟你在 Mac 上「隐私」里选的截屏档位、或你**事先用中文记下的截屏目标**有关），在同一线程里发**带坐标格子的图**。你在**这条线程**里用文字回坐标，例如 **「50，50」** 表示横、纵各 50（图上是 0～100 的尺子）；也支持带「横」「纵」的写法（细节以图下说明为准）。想再玩一轮可以说 **继续** 或 **再来一次**；说 **结束** 或 **停止** 就收工。Mac 上要开好 **屏幕录制** 和 **辅助功能**，Slack Bot 也要能上传图片。很久没人理的话，大约**五分钟**会超时。

    **本机「截屏类触发」还是关着的时候**  
    你可以先发中文 **「截屏目标主屏」**、**「截屏目标副屏」** 或 **「截屏目标焦点屏」**，只记「下次远程点屏先截哪块屏」，**不会**替你在 Mac 上偷偷打开自动截屏。

    **本机已经打开截屏类自动化时**  
    还可以用 Slack 再切「关 / 主屏 / 副屏 / 焦点屏」；**那句带英文前缀的完整写法同样只在「启用测试」后的工作台说明里写清**，这里不展开，免得误触。

    **盯屏（让七七帮你看屏幕）**  
    直接用**自然语言**说你想盯什么就行，例如「帮我看看下载进度条走完了没有」「屏幕上如果出现『完成』两个字就喊我」。七七会尽量听懂，在原消息下面回复确认；具体能盯什么、和模型看图的关系，见「智能体工作台 → **集成**」页。

    **想再看一遍这条说明**  
    在频道里发 **「帮助」**、**「使用说明」**、**「怎么用」** 之类，七七会再发一遍。
    """

    // MARK: - 启用测试：偏技术说明，含 `!pet` 指令与权限细节

    private static let integrationHelpMarkdownTesting: String = """
    🐱 **DesktopPet × Slack（技术说明 / 测试用）**

    **对话同步**  
    「智能体工作台 → 连接」：配置 Bot Token、监控频道 ID、**绑定** Slack 频道 ↔ 本地会话；按需打开入站 / 出站。首次连接某频道会跳过历史回放，仅同步之后的消息。

    **新建本地会话并绑定当前频道**  
    - **`!pet new`** 或 **`!pet new 标题`**：在本监控频道发送；标题可省略（默认「Slack 会话」）。会新建本地频道并写入绑定。

    **远程点屏**  
    - **入口**：`!pet click`、`!pet 点屏`，或中文整句 / 前缀触发（如 **远程点屏**、**远程点击**、**帮点一下屏幕** 等；关键词后须为空白或常见标点，勿与后续汉字紧邻，避免误触）。  
    - **流程**：同线程内上传带 **0–100** 标尺的截图（需 **屏幕录制** + Bot **files:write**；失败时仍可尝试纯文字坐标）。用户在**同一线程**回复坐标，例如 `50,50`、`50，50`、`x=0.5 y=0.5`（0–100 或 0–1）。  
    - **多轮**：`继续` / `再来一次` 重新截屏；可 `继续90，62` 沿用上一张图再点；`结束` / `停止` 退出会话。  
    - **权限**：执行点击需 **辅助功能**。约 **5 分钟**无操作超时。

    **截屏档位（Slack）**  
    - **总开关非「关」**：`!pet screen off` | `main` | `secondary` | `focus` 远程切换关 / 主屏 / 副屏 / 焦点屏。  
    - **总开关为「关」**：**不能**用 Slack 远程改为「开」；可 **`!pet screen pick main`** / **`pick secondary`** / **`pick focus`**，或中文 **「截屏目标主屏」** / **「截屏目标副屏」** / **「截屏目标焦点屏」**，仅记录下次远程点屏按哪块物理屏截（需已授权屏幕录制）。

    **盯屏**  
    - **`!pet watch …`** / **`!pet 盯屏 …`**，或自然语言（`shouldAttemptNaturalLanguageParse` 为真时走模型解析草稿）。仅 OCR + 可选多模态兜底（无进度条亮度启发式）；无需已绑定本地会话也会在原帖线程下 `ack`。

    **再看说明**  
    - 发 **`!pet help`** / **`!pet 帮助`**，或中文「帮助」「使用说明」「help」等。
    """

    private static func restMeaningless(_ rest: String) -> Bool {
        let s = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return true }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "，。！？、：；,.:!?;")).isEmpty
    }

    private static func matchesPhrasePrefix(_ t: String, phrase: String) -> Bool {
        guard t.hasPrefix(phrase) else { return false }
        if t.count == phrase.count { return true }
        guard let ch = t.dropFirst(phrase.count).first else { return true }
        return ch.isWhitespace || "，。！？、：；,.:!?;".contains(ch)
    }
}
