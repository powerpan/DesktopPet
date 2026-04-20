//
// AgentSettingsUICopy.swift
// 智能体工作台与菜单栏「DesktopPet」设置的双套文案：testing=true 偏技术/试跑；false 偏用户、七七桌宠口吻。
//

enum AgentSettingsUICopy {

    // MARK: - 菜单栏 · 系统设置面板

    static func settingsPanelHeaderLine1(testing: Bool) -> String {
        if testing {
            return "此处为 macOS 系统设置中的「DesktopPet」面板，只调整桌宠窗口本身：穿透、巡逻、宠物缩放、旁白气泡字号与桌镜。"
        }
        return "这里是系统里的「DesktopPet」小面板，只管桌宠窗口本身：要不要鼠标穿透、要不要巡逻、宠物有多大、旁白气泡字大不大、桌镜文字开关——像给七七整理小窝一样简单。"
    }

    static func settingsPanelHeaderLine2(testing: Bool) -> String {
        if testing {
            return "模型、API Key、Slack、会话、触发器、盯屏等请在菜单栏 **「打开智能体工作台…」**（独立窗口）；Slack 在「连接」分区配置。"
        }
        return "连模型、写对话、养七七、自动化和 Slack，都在菜单栏点 **「打开智能体工作台…」** 那个独立窗口里；Slack 去「连接」页找就好。"
    }

    /// 系统设置「条件旁白气泡字体」滑条下的说明（与宠物缩放独立）。
    static func settingsPanelBubbleFontCaption(testing: Bool) -> String {
        if testing {
            return "与「宠物缩放」解耦：仅影响条件触发时云朵气泡内**正文**相对系统 callout 的倍数；**1.0** 与未引入本滑条前的字号一致。范围 \(String(format: "%.1f", PetConfig.triggerBubbleFontScaleMin))～\(String(format: "%.1f", PetConfig.triggerBubbleFontScaleMax))×。"
        }
        return "这条只管**旁白气泡里的字**有多大，跟上面「宠物缩放」不是一回事。**1.0** 就是以前默认那种大小；想大一点再往右拖就好。"
    }

    static func settingsPanelTestingToggleFooter(testing: Bool) -> String {
        if testing {
            return "开启后：智能体工作台会显示更长、更偏开发与试跑的说明，并保留「试跑」、内部数值与调试块，便于自测与排查。"
        }
        return "关掉时：工作台用更短、更亲切的说明陪你看设置，隐藏试跑和太「工程师味」的块。日常撸猫建议关着；要查逻辑或压测再打开。"
    }

    static func settingsPanelAgentWorkshopFooter(testing: Bool) -> String {
        if testing {
            return "与上方面板分离：工作台含连接（含 Slack）、对话、陪伴、自动化与集成（盯屏）。"
        }
        return "和上面这块不一样：点按钮会打开「智能体工作台」，模型、聊天、陪伴、自动化、集成（盯屏）都在那儿。"
    }

    // MARK: - 工作台分区标题

    static func automationCenterSubtitle(testing: Bool) -> String {
        if testing {
            return "条件旁白、键盘与截屏等能力在此配置；隐私页含高风险总开关，请与触发器规则一并阅读。"
        }
        return "定时碎碎念、键盘小提醒、截屏看屏……都在这里配。别忘了去「隐私」看一眼总开关，七七会乖乖等你确认再干活。"
    }

    static func conversationCenterSubtitle(testing: Bool) -> String {
        if testing {
            return "频道、历史与清理在此；下方「人格」影响长对话与条件旁白的语气。"
        }
        return "聊天频道、历史记录和清理在这里；下面的「人格」会同时影响长聊天和条件旁白里七七怎么说话。"
    }

    // MARK: - 触发器 Tab

    static func triggersSlackFooter(testing: Bool) -> String {
        if testing {
            return "打开后，可在各条触发器编辑页开启「此条也发 Slack」；旁白仍照常显示气泡，并额外发到「连接」里填写的 Slack 监控频道（需已启用集成并配置 Bot Token）。盯屏任务仍只走任务自身的 Slack 汇报逻辑。"
        }
        return "打开后，单条规则里也可以勾选「这条也发到 Slack」，旁白照样冒泡，同时抄送一份到你填的监控频道（要先在「连接」里配好 Bot）。盯屏任务还是走自己的汇报，不会混进来。"
    }

    /// 测试模式：含试跑与占位符等技术说明。
    static func triggersIntroLinesTesting() -> [String] {
        [
            "触发器在满足条件时会自动请求模型写一句短旁白：写入旁白历史，并以宠窗旁云气泡展示。",
            "轻点气泡会关闭气泡、以该旁白为上下文新建一个手动会话频道，并打开对话面板续聊。",
            "在规则编辑页底部可点「立即触发当前触发器」，用当前表单内容向模型请求一次旁白（与自动触发相同链路），便于试跑提示语与路由。",
            "「饲养互动」在喂食/戳戳成功时请求旁白（不在此列表里自动轮询）；数值摘要写入模板占位符 {careContext}。「数值与成长旁白」在心情/能量偏低或成长随机事件时触发，上下文见 {statContext}；需在「陪伴 → 成长」打开数值旁白开关。两类规则首次升级各插入一条默认（默认关闭）。",
            "每条规则有独立冷却，避免刷屏。定时与随机空闲适合日常使用；键盘与前台应用属于进阶能力，请谨慎开启。",
        ]
    }

    /// 用户模式：不提「试跑」入口（与关闭测试时隐藏试跑 UI 一致）。
    static func triggersIntroLinesUser() -> [String] {
        [
            "七七会在条件满足时悄悄问模型要一句短旁白，记在旁白历史里，再用小气泡飘给你看。",
            "点一下气泡可以关掉它，并带着这句旁白开一个新聊天频道继续聊。",
            "喂食、戳戳成功时的旁白是「饲养互动」；心情或能量偏低、或有成长小事件时的旁白是「数值与成长旁白」，记得在「陪伴 → 成长」打开旁白开关。",
            "每条规则都有自己的冷却时间，避免刷屏。定时、随机空闲比较温和；键盘、前台应用更敏感，开之前想清楚哦。",
            "想试跑单条规则、看更长说明？在菜单栏 DesktopPet → 系统「设置」里打开「启用测试」即可。",
        ]
    }

    static func triggersDefaultParamsFooter(testing: Bool) -> String {
        if testing {
            return "仅作用于「条件触发 / 立即触发」的短旁白请求，与「连接」分区里长对话的温度、max_tokens 相互独立。各条触发器可在编辑页单独覆盖；未覆盖时使用这里的默认值。"
        }
        return "这些数字只影响「条件旁白」那种短请求；和「连接」里长聊天的温度、长度是两套设置。单条规则里也可以再覆盖。"
    }

    static func triggersListFooter(testing: Bool) -> String {
        if testing {
            return "macOS 上分组表单里通常没有「左滑删除」；请点每行右侧废纸篓图标，或在打开「编辑」后使用工具栏里的「删除」。"
        }
        return "Mac 上这里往往不能左滑删除，点每行右边的小垃圾桶，或进编辑页用工具栏删除。"
    }

    static func triggersKeyboardPrivacyAlertTitle() -> String { "请打开键盘模式总开关" }

    static func triggersKeyboardPrivacyAlertMessage(testing: Bool) -> String {
        if testing {
            return "你刚添加了「键盘模式」触发器，但「自动化」分区里「隐私」表单的「允许键盘模式触发」总开关仍为关闭，规则不会生效。请向下滚动到隐私说明并打开开关。"
        }
        return "你刚加了「键盘模式」规则，但「自动化 → 隐私」里「允许键盘模式触发」还没开，七七没法听键盘哦。往下滚到隐私页打开总开关就好。"
    }

    // MARK: - 隐私 Tab

    static func privacyAttachKeySummaryInline(testing: Bool) -> String {
        if testing {
            return "依赖桌镜的键位标签摘要，可能暴露你正在输入的大致内容；默认关闭。"
        }
        return "会用到桌镜里的按键摘要，可能让人猜到你大概在敲什么；默认关着更安全。"
    }

    static func privacyAttachKeySummaryFooter(testing: Bool) -> String {
        if testing {
            return "开启后，会把桌镜里显示的「键位标签摘要」拼进长对话的系统提示或触发旁白请求的 user 内容，仅在你主动发消息或触发器触发时才会上网。"
        }
        return "打开后，长对话或旁白请求里可能会带上桌镜里的按键摘要，只有你发消息或触发器触发时才会发给模型。"
    }

    static func privacyKeyboardMasterInline(testing: Bool) -> String {
        if testing {
            return "总开关关闭时，所有「键盘模式」类规则都不会匹配。"
        }
        return "关掉时，所有「听键盘」的规则都不会生效。"
    }

    static func privacyScreenSnapPickerInline(testing: Bool) -> String {
        if testing {
            return "「关」：不跑截屏类自动化、菜单栏截屏旁白；远程点屏仍可在有屏幕录制权限时按 Slack 记录的显示器偏好截屏。「截取主/副/焦点屏」：按所选方式截一张图（副屏需外接且系统可见；焦点屏按前台应用窗口所在显示器，与巡逻「焦点屏」一致）。"
        }
        return "选「关」就不跑截屏自动化和菜单栏截屏旁白；远程点屏在已授权时仍可按你在 Slack 里选的屏来截。「主屏 / 副屏 / 焦点屏」会真的去截对应显示器（副屏要接着；焦点屏跟前台大窗口在哪块屏）。"
    }

    static func privacyAdvancedSwitchesFooter(testing: Bool) -> String {
        if testing {
            return "键盘总闸：关闭后，所有「键盘模式」类触发器都不会匹配子串。截屏档位为「关」时不跑截屏自动化与菜单栏截屏旁白；为「主/副/焦点屏」时仍须系统「屏幕录制」权限及已启用的截屏规则。Slack 可在总开关为关时发「截屏目标主屏」等仅记录显示器偏好。"
        }
        return "键盘总开关关着，所有键盘类触发都不匹配。截屏选「关」就不跑截屏自动化；选主屏、副屏或焦点屏要系统「屏幕录制」权限和对应规则。关着截屏时仍可在 Slack 里发「截屏目标主屏」这类话，只记下偏好、不真的开自动化。"
    }

    static func privacyKeyboardRiskAlertMessage(testing: Bool) -> String {
        if testing {
            return "开启后，应用会监听全局按键以匹配你配置的「模式串」，用于触发智能体旁白。不会把原始键入全文写入磁盘；但仍属于敏感能力，请仅在信任本机与源码时使用。"
        }
        return "打开后，七七会在本机听按键是否匹配你写的「模式串」，好触发旁白。不会把整段打字存进磁盘，但这仍然是敏感能力，只在信任的电脑上开哦。"
    }

    static func privacyScreenSnapAlertMessage(testing: Bool) -> String {
        if testing {
            return "开启「截取主屏」「截取副屏」或「截取焦点屏」后，满足条件的「截屏」触发器会通过 ScreenCaptureKit 截取对应显示器画面，经缩放与 JPEG 压缩后，作为多模态请求的一部分发往你在「连接」里为**当前服务商**配置的 Base URL 与模型。画面可能包含屏幕上任何可见内容；请在会议或投屏场景改回「关」或关闭对应规则。默认不落盘原图。若模型不支持图像，应用会尝试自动改为纯文字重试一次。"
        }
        return "主屏、副屏或焦点屏档位打开后，截屏触发会拍对应显示器的一帧，压缩后发给当前模型，屏上能看见的都可能被看到；开会或投屏时请改回「关」或关掉规则。默认不把原图存磁盘；模型不认图时会自动试一次纯文字。"
    }

    // MARK: - 连接 Tab

    static func connectionProviderFooter(testing: Bool) -> String {
        if testing {
            return "每一套服务商各自保存 Base URL、模型 id 与 API Key。切换时会载入该套已保存的地址与模型；请为当前选中的服务商单独粘贴并保存 Key。"
        }
        return "每个服务商各有一套地址、模型名和 Key；切换标签会换一套存档，记得给当前选中的那套单独保存 Key。"
    }

    static func connectionServerFooterLines(testing: Bool) -> [String] {
        if testing {
            return [
                "Base URL：OpenAI 兼容 Chat Completions 的根地址，须含 https://，**不要**手动拼 `/v1/chat/completions`（应用会自动追加）。",
                "DeepSeek 示例：https://api.deepseek.com",
                "通义千问（DashScope 兼容模式）示例：https://dashscope.aliyuncs.com/compatible-mode；模型如 qwen-vl-plus（截屏多模态）、qwen-turbo 等以控制台为准。",
                "自定义：可填其它兼容网关；模型 id 填对方文档中的名称。",
            ]
        }
        return [
            "填 OpenAI 兼容接口的根地址，要有 https://，**不要**自己加 `/v1/chat/completions`，应用会自动拼。",
            "DeepSeek 示例：https://api.deepseek.com",
            "通义兼容模式示例：https://dashscope.aliyuncs.com/compatible-mode，具体模型名看控制台。",
            "其它网关照对方文档填根地址和模型 id 即可。",
        ]
    }

    static func connectionKeyFooter(testing: Bool) -> String {
        if testing {
            return "仅保存在本机钥匙串，不会写入 UserDefaults 或明文文件；各服务商使用不同钥匙串账户，互不影响。保存后若对话里仍提示未配置，可先关闭再打开对话面板刷新状态。"
        }
        return "Key 只存在本机钥匙串里，不会明文写在设置文件里。保存后若聊天里还说没配好，关掉再开一次对话面板试试。"
    }

    static func connectionSlackFooter(testing: Bool) -> String {
        if testing {
            return "在 Slack 监控频道发送 **`!pet new`** 或 **`!pet new 标题`** 可新建本地会话并绑定当前频道；标题可省略（默认「Slack 会话」）。首次连接某频道会跳过历史回放，仅同步之后的新消息。出站会把当前绑定频道内你发送的 user/assistant 消息同步回 Slack。入站/出站开关见上方 Toggle。"
        }
        return "打开入站、出站后，监控频道与桌宠里绑定的会话会互相同步；第一次连某个频道不会把旧消息全灌进来，只处理之后的新消息。若要从 Slack **再建一条新的本地会话并绑到这个频道**，需要桌宠能识别的**固定英文前缀**（避免日常误触发），日常模式不在此写出；请在本机 **系统设置 → DesktopPet** 打开 **启用测试** 后回到本页，在 Slack 小节查看**可复制整句**与标题示例。"
    }

    static func connectionGenerationFooterLines(testing: Bool) -> [String] {
        if testing {
            return [
                "温度：越高回答越随机、越有创意；越低越保守、越稳定。一般聊天约 0.6～0.9。",
                "max_tokens：模型单次回复最多生成的 token 数（约等于字数上限）；越大越耗额度与等待时间。",
            ]
        }
        return [
            "温度高一点，七七说话更活泼、更随机；低一点更稳重。日常聊天 0.6～0.9 左右就挺好。",
            "max_tokens 是单次回复大概能写多长；设太大更费钱也更久。",
        ]
    }

    // MARK: - 人格 / 会话

    static func personaFooter(testing: Bool) -> String {
        if testing {
            return "每次请求都会作为 system 消息发给模型，用来设定语气、称呼、回答语言等；对话面板里的聊天内容会接在它的后面。条件触发的旁白请求会把同一段人格文字拼在 user 消息最开头（旁白单独走一套温度与 max_tokens，见「自动化」分区），与长对话的 system 用法区分开。"
        }
        return "这里写的人设会作为 system 发给模型，决定七七怎么称呼你、用什么语气。长聊天和条件旁白都会读到它；旁白那套温度和长度在「自动化 → 触发器」里另算。"
    }

    static func sessionHistoryFooter(testing: Bool) -> String {
        if testing {
            return "多会话频道与消息保存在 UserDefaults；「清空当前频道」只影响当前选中会话。「旁白历史」记录模型返回的旁白正文；「发给模型的请求」记录同一次触发里作为 user 发给大模型的全文（占位符已替换，最多约 200 条与旁白历史共用条数）。清空旁白历史会同时清空这两类展示所依赖的数据。重置会话会删除所有频道并恢复为单一空会话。在旁白历史或请求列表中可按「发送类型」（触发器种类）筛选。"
        }
        return "频道和消息存在本机偏好里。「清空当前频道」只动你正在看的那个频道。旁白历史和「发给模型的请求」是两套记录，但清空旁白历史会一起清掉它们依赖的数据；重置会话会把所有频道删掉恢复成一个新的空频道。列表里可以按触发类型筛选。"
    }

    // MARK: - 陪伴 · 成长

    static func growthCatInteractFooter(testing: Bool) -> String {
        if testing {
            return "喂食：5 分钟～24 小时（用「小时 + 分钟」选择；满 24 小时时分钟固定为 00）。戳戳：5～600 秒。会写入本机偏好，重启后仍生效；冷却中是否立刻按新值生效取决于距离上次操作的时间。"
        }
        return "喂食间隔在 5 分钟到 24 小时之间用「小时+分钟」选；戳戳冷却 5～600 秒。改完会记住，重启也在；如果正在冷却中，新数字要等你这一轮过去才完全按新的算。"
    }

    static func growthParamsFooter(testing: Bool) -> String {
        if testing {
            return "每小时衰减在宠物隐藏时也会累计。喂食/戳戳增量为 0～1 刻度上的一次成功加成（默认与旧版一致：喂食 +12% 心情、+15% 能量；戳戳 +6% 心情、能量 0%）。若距离上次结算已超过 3 小时（例如久未打开应用），只会按小时补扣心情/能量，不会补抽随机事件；回到 3 小时内后恢复按密度抽样（午间等时段略更容易）。密度 100% 且时段加权最高时，「每小时最多一次」随机尝试的成功概率上限约 90%。开启 AI 后，部分事件会请求模型生成 JSON（失败则自动用本地事件）；会消耗 API。"
        }
        return "七七藏起来的时候，心情和能量也会慢慢掉。喂食、戳戳会按滑条加回来。好久（超过大约 3 小时）没打开应用，只会补扣心情和能量，不会一口气补很多随机小事件；回到正常节奏后，随机事件再按密度抽。把随机密度拉满也不会每分钟都炸事件，仍然有上限。打开 AI 成长时偶尔会问模型要 JSON，失败就用本地小故事，会走一点 API。"
    }

    static func growthStatNarrativeFooter(testing: Bool) -> String {
        if testing {
            return "心情或能量低于阈值时会像「诉苦」一样请求一句旁白；发生本地或 AI 成长随机事件时也会带事件摘要请求旁白。需在「自动化 → 触发器」中启用「数值与成长旁白」规则（并配置模型）；请求失败时应用会用本地兜底句。与下方冷却共同限制频率。"
        }
        return "心情或能量太低时，七七可以嘟囔一句求安慰；有成长小事件时也会顺便要一句旁白。记得在「自动化 → 触发器」里打开「数值与成长旁白」并配好模型；失败了会用本地兜底句子。和下面的最短间隔一起限频。"
    }

    static func growthStatsPreviewFooter(testing: Bool) -> String {
        if testing {
            return "陪伴时长仅在宠物窗口可见时累计；统计按本机日历日写入。"
        }
        return "只有宠物窗口在屏幕上时才算「陪着」；统计按你电脑上的日历天记。"
    }

    static func growthRecentEventsFooter(testing: Bool) -> String {
        if testing {
            return "事件会轻微调整心情/能量并记入当日统计；列表最多保留 80 条。"
        }
        return "每条小事件会轻轻动一下心情和能量，并记进今天的账里；列表最多留 80 条。"
    }

    static func growthDebugSectionFooter(testing: Bool) -> String {
        if testing {
            return "关闭「试跑使用 AI」时，只调用本地事件池与随机数；打开时每次点击都会向当前 Base URL / 模型发一次 JSON 试跑请求（不写回状态）。两种模式均不修改 lastDecayAt 与心情/能量。"
        }
        return "（仅测试模式可见）试跑不会真的改七七的心情和能量，也不会动内部时间锚点。"
    }

    // MARK: - 集成 Tab

    static func integrationsMultimodalIntro(testing: Bool) -> String {
        if testing {
            return "同时作用于对话面板「+」上传与 Slack 入站附件；超出限额时不会在 Slack 调用模型，并在对应线程回复原因。"
        }
        return "对话里点「+」传图、以及 Slack 里收到的附件，都受这些上限管；超了就不会去调用模型，并在 Slack 线程里说明原因。"
    }

    static func integrationsMultimodalFooter(testing: Bool) -> String {
        if testing {
            return "Slack 侧需为 Bot 配置 **files:read**（及可访问 files.slack.com 私有下载链接），否则无法下载频道内图片/文件。"
        }
        return "Slack Bot 要有读文件的权限，否则频道里的图和文件下不下来。"
    }

    static func integrationsRemoteClickBody(testing: Bool) -> String {
        if testing {
            return "在监控频道发送 **`!pet click`** / **`!pet 点屏`**，或整句以中文触发词开头（例如 **远程点屏**、**远程点击**、**帮点一下屏幕**、**猫猫远程点屏**、**屏幕远程点击** 等；关键词后须为空白或常见标点，勿与后续汉字紧邻，避免误触）。应用按「隐私」中截屏档位或 Slack 已记录的显示器偏好截取 **主屏 / 副屏 / 焦点屏**，并在线程内上传带 **0–100** 标尺的 JPEG（需 **屏幕录制** + Bot **files:write**；上传失败时仍可尝试纯文字坐标）。在**同一线程**回复坐标，例如 **`50,50`**、**`50，50`**、**`x=0.5 y=0.5`**（0–100 或 0–1；越界会报错）。多轮：**继续** / **再来一次** 重新截屏；**继续90，62** 可沿用上一张图直接再点；**结束** / **停止** 退出。**点击执行**依赖 **辅助功能**。约 **5 分钟**无操作超时。\n\n**截屏档位（Slack）**：总开关非「关」时可用 **`!pet screen off`** / **`main`** / **`secondary`** / **`focus`** 远程切换；总开关为「关」时**不能**远程改为「开」，但可用 **`!pet screen pick main`** / **`pick secondary`** / **`pick focus`** 或中文 **「截屏目标主屏」** / **「截屏目标副屏」** / **「截屏目标焦点屏」** 仅记录下次按哪块物理屏截。"
        }
        return "在已启用 Slack 的**监控频道**里，用**中文**发起即可，例如 **「远程点屏，」**、**「远程点击，」**、**「帮点一下屏幕，」**、**「猫猫远程点屏，」**（**词后请立刻接逗号、句号或空格**，不要和后面的汉字粘在一起，例如别说「远程点屏谢谢」）。七七会截一帧当前该截的屏幕（与 Mac 上「自动化 → 隐私」里截屏档位一致；若本机总开关仍是关，可事先在频道发 **「截屏目标主屏」**、**「截屏目标副屏」** 或 **「截屏目标焦点屏」** 只记偏好），在**同一条线程**里发带坐标格的图。你在该线程用文字回坐标，例如 **「50，50」** 表示横纵各 50。想再来一轮说 **继续** 或 **再来一次**；说 **结束** 或 **停止** 结束。需要 **屏幕录制**、**辅助功能**，以及 Bot 能上传文件。约 **五分钟**无操作会超时。\n\n若本机「截屏类触发」**已打开**，还可通过 Slack 用**英文前缀句式**在「关 / 主屏 / 副屏 / 焦点屏」之间切换；**完整句式仅在系统设置 → DesktopPet → 启用测试 后，于本页测试模式说明中展示**，日常说明不写英文口令以免误触。"
    }

    static func integrationsRemoteClickSelfTest(testing: Bool) -> String {
        if testing {
            return "自测清单（建议顺序）：① **`!pet click`** 或 **`!pet 点屏`**（或中文触发）应在线程内出现坐标图；② 回复 **`50,50`** 应执行点击并询问是否继续；③ **继续** 应再截一帧并上图；④ **结束** 应退出远程点屏会话；⑤ **`x=1.2 y=0`** 类越界应报错且不点击；⑥ 关闭辅助功能后应仅回帖提示授权；⑦ 总开关为关时 **`!pet screen main`** 应被拒绝，但 **`!pet screen pick secondary`** / 中文「截屏目标副屏」应可写入偏好。"
        }
        return ""
    }

    static func integrationsWatchTasksIntro(testing: Bool) -> String {
        if testing {
            return "需已授予「屏幕录制」权限。本地 OCR / 进度条亮度启发式优先；可选多模态模型 YES/NO 兜底（消耗 API）。"
        }
        return "要先有「屏幕录制」权限。七七会尽量用本机识字和看进度条；实在拿不准再请模型帮一把（会走 API）。"
    }

    static func integrationsWatchTasksFooter(testing: Bool) -> String {
        if testing {
            return "启用进度条启发式时，请在主屏拖拽框选区域（Esc 取消）；无需手填数字。模型兜底在本地未命中时才会调用。已添加的任务可点「编辑」修改条件、兜底说明、是否重复使用及间隔。"
        }
        return "进度条那块用主屏拖拽框一下就行（Esc 取消），不用手抄数字。模型只在本地条件对不上时才出场。加好的任务可以随时点「编辑」改条件或冷却。"
    }

    static func integrationsVisionCooldownClockHint(testing: Bool) -> String {
        if testing {
            return "秒为钟表意义上的 0…59；总间隔最长 24 小时。仅当本地条件未全部满足时才会请求模型。"
        }
        return "秒数是 0…59 那种；整段冷却最长一天。只有本地没看准时才会去问模型。"
    }

    /// 进度条：算法说明（第一段）
    static func watchProgressBarAlgorithmPrimary(testing: Bool) -> String {
        if testing {
            return "把整条进度条框进矩形。算法取该区域最左 1/5 与最右 1/5 的平均亮度（约 0=黑、1=白）。常见「从左往右填满」时：未完成往往左右一边更亮、差较大；走完后整条颜色接近一致，差会变小。当「左右平均亮度差的绝对值」≤ 下方阈值时，判定为接近/已完成。"
        }
        return "把整条进度条框进矩形里。七七会偷偷比较条子左边和右边亮不亮，差得大往往还没跑满，差得小可能就快好了；具体阈值在下面滑。"
    }

    /// 进度条：阈值与误判说明（第二段）
    static func watchProgressBarAlgorithmSecondary(testing: Bool) -> String {
        if testing {
            return "默认 0.08：左右平均亮度最多相差约 8 个百分点即视为「够均匀」。阈值越大越容易满足（更早触发）；越小越严格。为避免 0% 时整条底轨已很均匀而误判，会先要求在本任务运行期间出现过一次「左右明显不对称」，再接受「够均匀」；若从接近 100% 才开始盯屏，可能一直不满足，请配合 OCR 或模型兜底。"
        }
        return "数字默认约 8% 的意思是：左右亮度差小到这份上就算「够均匀」。调大更容易触发，调小更严格。为了避免一开头底轨就很平被误判，会先等任务跑一会儿、看到过一次「左右不一样亮」，再认「变均匀了」。如果从快满才开始盯，有可能一直对不上，可以配合文字 OCR 或模型兜底。"
    }

    static func integrationsWatchRepeatCooldownHint(testing: Bool) -> String {
        if testing {
            return "可重复时两次命中之间的最短等待，避免条件一直为真时连续旁白。"
        }
        return "勾了「可重复」时，两次命中之间至少要隔这么久，免得条件一直成立就刷屏。"
    }

    static func screenWatchSlackAutomatedNotice(testing: Bool) -> String {
        if testing {
            return "此任务来自 Slack 自动盯屏，仅支持 OCR 与模型兜底，不包含进度条亮度启发式；保存时会移除已误存的进度条件。"
        }
        return "这条是 Slack 里让七七盯屏时自动建的，只支持识字和模型兜底，没有进度条亮度那一套；保存时会清掉误加的进度条件。"
    }

    static func screenWatchRepeatFooterHint(testing: Bool) -> String {
        if testing {
            return "两次旁白/命中之间的最短等待，避免条件一直为真时连续刷屏。"
        }
        return "两次命中之间至少隔这么久，避免一直满足就一直叨叨。"
    }

    // MARK: - 触发器编辑 Sheet

    static func triggerEditorBasicFooter(testing: Bool) -> String {
        if testing {
            return "冷却：两次触发之间的最短间隔（秒）。触发一次后会进入冷却，期间即使条件仍满足也不会再请求。"
        }
        return "冷却是两次触发之间至少要隔这么多秒；冷却里就算条件还成立，七七也不会连着问模型。"
    }

    static func triggerEditorSlackFooter(masterOn: Bool, testing: Bool) -> String {
        if !masterOn {
            return testing
                ? "请先在「触发器」列表顶部的 Slack 区域打开「触发旁白也推送到 Slack」总开关，再为各条规则单独开启。"
                : "请先在触发器列表最上面打开「旁白也发 Slack」总开关，再在这里勾选。"
        }
        return testing
            ? "开启后，本条触发产生的旁白除气泡外，会发到「连接」里配置的 Slack 监控频道（需 Bot Token 与频道 ID）。"
            : "打开后，这条规则触发的旁白除了气泡，还会抄送到你在「连接」里配好的 Slack 频道（要有 Bot 和频道 ID）。"
    }

    static func triggerEditorKeyboardBlockedCallout(testing: Bool) -> String {
        if testing {
            return "「隐私」Tab 中的「允许键盘模式触发」总开关当前为关闭，本键盘规则不会匹配按键。请切换到「隐私」阅读风险提示后打开开关。"
        }
        return "「自动化 → 隐私」里「允许键盘模式触发」还关着，这条键盘规则不会生效。去隐私页看一眼说明再打开就好。"
    }

    static func triggerEditorDefaultTemplateFooter(testing: Bool) -> String {
        if testing {
            return "发给模型的一条 user 消息（user role）。当没有任何旁白路由的条件被满足时，使用本模板。整段留空则使用应用内置默认句式。"
        }
        return "没有路由命中时，就用这段当发给模型的用户话；全空则用内置默认句式。"
    }

    static func triggerEditorRoutesFooterLine1(testing: Bool) -> String {
        if testing {
            return "每条路由内多个条件为 AND。键盘类路由至少包含一个「按键包含」且子串非空，否则不会匹配。同一次触发只选用一条路由的提示语。"
        }
        return "同一条路由里多个条件是「都要满足」。键盘类至少要有一个非空的「按键包含」。每次触发只会用一条路由的提示。"
    }

    static func triggerEditorRoutesFooterLine2(testing: Bool) -> String {
        if testing {
            return "删除：点每行右侧废纸篓；macOS 分组表单里左滑删除往往不可用。"
        }
        return "删路由点右边垃圾桶；这里往往不能左滑删除。"
    }

    static func triggerEditorRoutesEmptyHint(testing: Bool) -> String {
        if testing {
            return "尚未配置路由：将使用上方默认模板；键盘类还可回退到下方「旧版单一模式串」。"
        }
        return "还没配路由：会用上面的默认模板；键盘类还能退回下面旧版的一条模式串。"
    }

    static func triggerEditorTimerFooter(testing: Bool) -> String {
        if testing {
            return "从上一次触发完成起算，每隔这么多分钟最多触发一次（仍受冷却下限约束）。"
        }
        return "从上一次触发完算起，每隔这么多分钟最多来一次（还要满足上面的冷却）。"
    }

    static func triggerEditorRandomIdleFooterLines(testing: Bool) -> [String] {
        if testing {
            return [
                "仅在宠物窗口可见时评估。空闲秒数：无键鼠活动达到该秒数后才可能触发。",
                "概率：每次抽样时掷骰，数值越大越容易触发；建议保持较低以免打扰。",
                "同一段键鼠静止期内：每条「随机空闲」规则在成功旁白一次后会暂停，直到你再次键鼠活动后才会重新参与随机判定（仍须满足冷却与最小间隔）。",
            ]
        }
        return [
            "只有宠物窗口在屏幕上时才会数空闲；键鼠安静够这么多秒才可能抽中。",
            "概率越大越容易冒泡，建议别拉太高，免得吵到你。",
            "同一段「你不动」的时间里，每条随机空闲规则成功一次后会先歇着，等你再动一动键鼠才会重新参与抽奖。",
        ]
    }

    static func triggerEditorKeyboardCompatFooterLine1(testing: Bool) -> String {
        if testing {
            return "推荐在「旁白路由」里为不同子串配置不同提示语；优先级数字越大越先匹配。此处旧字段仅在路由表为空时作为单条子串回退；大小写敏感。需已授予辅助功能。"
        }
        return "更推荐用上面的「旁白路由」给不同按键配不同台词；下面这格只在没配路由时当一条老模式串用，区分大小写。需要辅助功能权限。"
    }

    static func triggerEditorKeyboardCompatFooterMasterOff(testing: Bool) -> String {
        if testing {
            return "总开关关闭时引擎不会评估键盘子串；请务必到「隐私」打开「允许键盘模式触发」。"
        }
        return "总开关关着时七七不会听键盘；请到「隐私」打开「允许键盘模式触发」。"
    }

    static func triggerEditorKeyboardCompatInline(testing: Bool) -> String {
        if testing {
            return "仅匹配模式串（最近按键缓冲），不保存全文日志。需打开「隐私」中的总开关。"
        }
        return "只匹配最近按键缓冲里的子串，不存全文。要在「隐私」里打开总开关。"
    }

    static func triggerEditorFrontAppFooter(testing: Bool) -> String {
        if testing {
            return "推荐在「旁白路由」里用「前台包含」条件写多条。此处旧字段仅在路由表为空时回退；切换应用时大小写不敏感匹配本地化名称。"
        }
        return "更推荐用旁白路由里的「前台包含」写多条；这格只在没路由时当一条回退；应用名不区分大小写。"
    }

    static func triggerEditorScreenSnapFooterLines(testing: Bool) -> [String] {
        if testing {
            return [
                "冷却下限请使用上方「基本」中的「冷却（秒）」；与「成功旁白最短间隔」取**更长**者作为实际上限。",
                "JPEG 质量系数（0.55～0.85）：与 macOS 编码 JPEG 时的 compressionFactor 一致，表示有损压缩的轻重，不是分辨率。系数越高，同一截屏下画质越好、文件越大、上传越慢、API 请求体越大；越低则相反。与上方「长边上界」共同影响模型能否看清屏上小字。",
                "自动触发需打开「隐私」中的截屏档位（主/副/焦点屏），并授予屏幕录制。本条「截取显示器」可选跟随隐私档位或单独指定主屏、副屏、焦点屏（与巡逻「焦点屏」同源：前台应用大窗所在显示器）。所选显示器经 ScreenCaptureKit 抓取后按「长边上界」缩放再 JPEG 编码（最大 2048px），仅在内存中上传；长边越大越利于认字，但请求体与耗时通常也会增加。",
                "若模型不支持图像，应用会在收到 HTTP 400 时自动改为纯文字再请求一次。",
            ]
        }
        return [
            "最短间隔和上面的「冷却」两个里取更长的那个，才是真正要等多久。",
            "JPEG 质量越高图越清楚、请求越大；和「长边上界」一起决定模型能不能看清小字。",
            "自动截屏要在「隐私」里打开主屏、副屏或焦点屏档位，并给好屏幕录制权限；下面「截取显示器」可再细调本条是跟隐私还是固定某一档。图只在内存里上传，不默认存盘。",
            "模型不认图时会自动试一次纯文字。",
        ]
    }

    static func triggerEditorCareInline1(testing: Bool) -> String {
        if testing {
            return "由饲养面板的「喂食」「戳戳」在**成功生效**后触发（动作处于冷却失败时不会请求模型）。应用会把当前心情、能量、今日陪伴时长及本次数值变化写入旁白模板的 {careContext}。"
        }
        return "喂食、戳戳**真的加上去了**才会触发；在冷却里点空不会问模型。心情、能量、陪伴时长等会写进模板里的 {careContext}。"
    }

    static func triggerEditorCareInline2(testing: Bool) -> String {
        if testing {
            return "冷却：两次饲养旁白请求之间的最短间隔；与喂食 4 小时、戳戳 30 秒的动作冷却无关，用于防止连点造成重复请求。"
        }
        return "这里的冷却是「两句饲养旁白之间」的间隔，和喂食/戳戳动作本身的冷却不是一回事，用来防连点刷屏。"
    }

    static func triggerEditorCareFooter(testing: Bool) -> String {
        if testing {
            return "列表中若有多条「饲养互动」规则，仅**第一条已启用**的会收到面板事件；可在模板中用 {careContext}、{extra}、{matchedCondition} 等占位符。"
        }
        return "如果列表里有多条饲养互动，只有**第一条开着的**会收到事件；模板里照常写占位符即可。"
    }

    static func triggerEditorPetStatInline1(testing: Bool) -> String {
        if testing {
            return "由「陪伴 → 成长」中的「数值旁白自动化」在心情/能量低于阈值或发生成长随机事件时触发。应用将说明写入 {statContext}；模型失败时会用本地兜底短句。"
        }
        return "在「陪伴 → 成长」打开数值旁白后，心情/能量太低或有成长小事件时会触发；说明写在 {statContext} 里，模型挂了用本地短句兜底。"
    }

    static func triggerEditorPetStatInline2(testing: Bool) -> String {
        if testing {
            return "成长 Tab 里另有「最短间隔」分钟数，与上方「冷却」共同限制频率；仅**第一条已启用**的本类型规则会收到事件。"
        }
        return "成长页里还有最短间隔，和上面的冷却一起限频；同样只有**第一条开着的**规则会收到事件。"
    }

    static func triggerEditorPetStatFooter(testing: Bool) -> String {
        if testing {
            return "可与 {extra}、{matchedCondition} 等占位符组合；建议语气偏撒娇、诉苦，一两句即可。"
        }
        return "可以和 {extra}、{matchedCondition} 等占位符混着写；一两句撒娇、诉苦就很好。"
    }

    static func triggerEditorPerRuleGenFooter(testing: Bool) -> String {
        if testing {
            return "关闭开关时使用「触发器」Tab 的默认温度与 max_tokens。从气泡进入长对话后，发送消息仍使用「连接」Tab 的设置。"
        }
        return "关掉就用触发器列表上面的默认温度和长度；从气泡跳进长聊天后，发消息还是走「连接」那套。"
    }

    static func triggerEditorTryRunFooter(testing: Bool) -> String {
        if testing {
            return "使用当前编辑页中的表单内容（含未点「完成」的修改）向模型请求一次旁白；成功后会出现旁白气泡并写入「旁白历史」与「发给模型的请求」。截屏类在成功收到模型回复后才更新「上次触发」。路由会先按当前环境匹配；若无命中则回退第一条启用路由。截屏试跑需打开隐私总开关并已授予屏幕录制；正在发送时按钮不可用。"
        }
        return ""
    }

    static func triggerEditorKeyboardSaveAlertMessage(testing: Bool) -> String {
        if testing {
            return "「隐私」Tab 中的「允许键盘模式触发」仍为关闭，键盘规则不会生效。若要启用匹配，请切换到「隐私」阅读说明并打开总开关。"
        }
        return "「隐私」里键盘总开关还关着，这条规则不会生效。要去隐私页打开才能真的听键盘。"
    }

    // MARK: - 旁白路由编辑 Sheet

    static func triggerRouteTemplateFooter(testing: Bool) -> String {
        if testing {
            return "若本路由模板整段留空，触发时会回退到上方的「默认旁白请求」模板。"
        }
        return "这条如果全空，就会用上面「默认旁白请求」那段的字。"
    }

    static func triggerRouteConditionsFooter(testing: Bool) -> String {
        if testing {
            return "键盘类触发器：至少保留一个「按键包含」且子串非空，否则该路由不会参与匹配。"
        }
        return "键盘类至少要留一个非空的「按键包含」，否则这条路由不会参与匹配。"
    }

    static func triggerRouteUnconditionalHint(testing: Bool) -> String {
        if testing {
            return "无条件：等价于「始终」匹配（键盘类规则请勿留空条件，请添加「按键包含」）。"
        }
        return "「无条件」等于一直为真；键盘类别这么干，请加「按键包含」。"
    }

    // MARK: - 占位符帮助（拆成段落）

    static func promptPlaceholderIntro(testing: Bool) -> String {
        if testing {
            return "占位符（须一字不差、含花括号）可在模板任意位置插入；未写的占位符不会出现在最终发给模型的文字里。"
        }
        return "花括号里的占位符可以插在模板任意位置，字要一模一样；没写的占位符不会出现。"
    }

    static func promptPlaceholderBullets(testing: Bool) -> [String] {
        if testing {
            return [
                "{extra} — 由应用自动拼好的一段「场景说明」：固定带有「（系统触发：某某类型）」；若你在「隐私」里打开了「附带键入摘要」，也会把截断后的键位摘要接在这同一段后面。建议保留，方便模型知道是谁在触发。",
                "{triggerKind} — 替换为当前规则的类型中文名，例如「键盘模式」「定时」「随机空闲」。",
                "{matchedCondition} — 替换为本次命中的那条旁白路由的条件摘要（例如「按键含「abc」且 空闲≥120s」），便于模型理解命中分支。",
                "{keySummary} — 仅键入摘要的短片段（与 {extra} 里可能带的摘要同源）；未开「附带键入摘要」时为空字符串。适合在模板中间单独引用摘要、而不想整段复述 {extra} 时使用。",
                "{careContext} — 仅「饲养互动」类型：喂食或戳戳成功时，由应用自动填入心情/能量变化与陪伴时长等摘要；未触发饲养操作或试跑占位时可能为空。",
                "{statContext} — 仅「数值与成长旁白」：心情/能量偏低或成长随机事件时，由应用填入结构化说明；未触发时为空。",
                "{screenCaptureMeta} — 仅「截屏」类型：应用填入时间、前台应用名、缩放与是否降级为纯文字等摘要；勿在模板中手写该占位符以外的机密内容。",
            ]
        }
        return [
            "{extra} — 一小段场景说明，会带上触发类型；开了键入摘要时也会把摘要接在后面，建议留着。",
            "{triggerKind} — 当前是哪种触发，比如定时、键盘。",
            "{matchedCondition} — 这次命中了哪条路由条件的摘要。",
            "{keySummary} — 只有键入摘要那一小段（和 {extra} 里可能重复同源）。",
            "{careContext} — 饲养互动专用：喂食/戳戳成功时的数值摘要。",
            "{statContext} — 数值与成长旁白专用：心情、能量或小事件说明。",
            "{screenCaptureMeta} — 截屏专用：时间、前台应用、缩放等元信息。",
        ]
    }

    static func promptPlaceholderExample(testing: Bool) -> String {
        if testing {
            return "示例：「用户可能刚输入了敏感内容。{extra} 请用两句简体中文温柔提醒。」若不写任何占位符，则整段模板会原样作为 user 消息发送。"
        }
        return "例如：「用户可能刚输入了敏感内容。{extra} 请用两句简体中文温柔提醒。」什么都不写也可以，整段会原样发给模型。"
    }

    // MARK: - JPEG 质量滑条旁注

    static func screenSnapJPEGQualityBand(quality: Double, testing: Bool) -> String {
        let v = min(0.85, max(0.55, quality))
        let band: String
        if v < 0.62 {
            band = testing
                ? "压缩偏强：上传更快、更省流量，界面小字与细边更容易出现马赛克。"
                : "压得狠一点：上传快、省流量，小字可能略糊。"
        } else if v < 0.72 {
            band = testing
                ? "折中：体积与清晰度较均衡，多数截屏旁白够用。"
                : "折中：大多数截屏够用。"
        } else if v < 0.80 {
            band = testing
                ? "偏清晰：文字与边缘更利落，请求体与耗时通常增加。"
                : "更清晰：字更利，但图更大、更慢一点。"
        } else {
            band = testing
                ? "接近上限：尽量保细节，JPEG 与 Base64 请求体会明显变大。"
                : "尽量保细节：文件会明显变大。"
        }
        return "当前 \(String(format: "%.2f", v))（约 \(String(format: "%.0f", v * 100))% 强度）— \(band)"
    }
}
