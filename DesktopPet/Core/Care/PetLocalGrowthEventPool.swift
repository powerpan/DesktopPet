//
// PetLocalGrowthEventPool.swift
// 预设「成长/小意外」事件：多文案变体、时段加权、抽样时权重微抖动以增加新鲜感。
//

import Foundation

private struct LocalGrowthTemplate {
    let code: String
    let textVariants: [String]
    let moodDelta: ClosedRange<Double>
    let energyDelta: ClosedRange<Double>
    /// 在哪些本地小时更容易出现（空 = 任意时刻都可出现）
    let preferredHours: Set<Int>?
}

enum PetLocalGrowthEventPool {
    private static let templates: [LocalGrowthTemplate] = [
        LocalGrowthTemplate(
            code: "missed_lunch",
            textVariants: [
                "到点没吃上饭，肚子咕咕叫，有点委屈。",
                "午饭便当推迟了，盯空碗开始怀疑人生。",
                "微波炉叮在隔壁，自己的碗还凉着，emo 一秒。",
                "人类开会说「马上吃」，猫猫的「马上」已经过期。",
            ],
            moodDelta: -0.06 ... -0.02,
            energyDelta: -0.12 ... -0.05,
            preferredHours: Set(11 ... 14)
        ),
        LocalGrowthTemplate(
            code: "tummy_trouble",
            textVariants: [
                "大概是吃坏了小肚子，蔫蔫地想趴着。",
                "偷尝了不该尝的 crumbs，肠胃在抗议。",
                "今天肠道像在打雷，只想团成球。",
                "酸奶盖舔太狠，后续有点不听指挥。",
            ],
            moodDelta: -0.08 ... -0.03,
            energyDelta: -0.18 ... -0.08,
            preferredHours: nil
        ),
        LocalGrowthTemplate(
            code: "afternoon_slump",
            textVariants: [
                "午后犯困，眼皮打架，能量条偷偷溜走。",
                "三点一刻，全世界只剩哈欠。",
                "阳光太好，CPU 降频成省电模式。",
                "咖啡味只在空气里，不在胃里。",
            ],
            moodDelta: -0.04 ... -0.01,
            energyDelta: -0.1 ... -0.04,
            preferredHours: Set(13 ... 17)
        ),
        LocalGrowthTemplate(
            code: "lonely_window",
            textVariants: [
                "窗外人来人往，独自叹气，心情略低落。",
                "鸽子路过都不停，社交 KPI 未达标。",
                "玻璃把热闹隔成静音频道。",
                "对面楼灯一盏盏亮，自己的影子有点长。",
            ],
            moodDelta: -0.07 ... -0.03,
            energyDelta: -0.05 ... -0.02,
            preferredHours: Set(16 ... 21)
        ),
        LocalGrowthTemplate(
            code: "night_owl_regret",
            textVariants: [
                "熬夜刷存在感，结果早上起不来，心情小崩。",
                "追更追到宇宙尽头，醒来发现是地球早晨。",
                "凌晨三点灵感爆棚，七点只想装死。",
                "生物钟被拖进异次元，正在慢慢爬回来。",
            ],
            moodDelta: -0.06 ... -0.02,
            energyDelta: -0.14 ... -0.06,
            preferredHours: Set([0, 1, 2, 23])
        ),
        LocalGrowthTemplate(
            code: "zoomies_crash",
            textVariants: [
                "刚才疯跑太嗨，现在电量见底，瘫成一张猫饼。",
                "客厅折返跑锦标赛刚闭幕，奖牌是喘气。",
                "动能守恒：刚才多疯，现在多扁。",
                "尾巴雷达全开之后，系统需要散热。",
            ],
            moodDelta: -0.02 ... 0.0,
            energyDelta: -0.15 ... -0.08,
            preferredHours: nil
        ),
        LocalGrowthTemplate(
            code: "hairball_drama",
            textVariants: [
                "舔毛工程过量，咳两下，今天能量不太够用。",
                "毛球 KPI 超额完成，代价是形象管理崩盘。",
                "自我清洁走火入魔，喉咙提出抗议。",
                "春天在胃里提前到货。",
            ],
            moodDelta: -0.04 ... -0.01,
            energyDelta: -0.1 ... -0.05,
            preferredHours: nil
        ),
        LocalGrowthTemplate(
            code: "stranger_doorbell",
            textVariants: [
                "门铃一响，警戒拉满，紧张完就累了。",
                "快递脚步逼近，战术匍匐已耗尽电量。",
                "访客按错门铃，心跳多跑五公里。",
                "门外是风，脑内是警匪片。",
            ],
            moodDelta: -0.05 ... -0.02,
            energyDelta: -0.08 ... -0.03,
            preferredHours: Set(9 ... 20)
        ),
        LocalGrowthTemplate(
            code: "vacuum_neighbor",
            textVariants: [
                "邻居吸尘器开工，猫猫怀疑地板要起飞。",
                "低频轰鸣像母舰降落，先躲为敬。",
                "地毯被公开处刑，旁听席压力山大。",
            ],
            moodDelta: -0.06 ... -0.02,
            energyDelta: -0.07 ... -0.03,
            preferredHours: Set(9 ... 18)
        ),
        LocalGrowthTemplate(
            code: "screen_cursor_chase",
            textVariants: [
                "光标在屏幕上瞬移，眼睛跟丢，自尊心碎一地。",
                "鼠标箭头像逗猫棒，可惜是二维骗局。",
                "窗口最小化那一下，信仰也最小化了。",
            ],
            moodDelta: -0.03 ... -0.01,
            energyDelta: -0.09 ... -0.04,
            preferredHours: Set(10 ... 22)
        ),
        LocalGrowthTemplate(
            code: "sunbeam_moved",
            textVariants: [
                "阳光带挪了位，暖炉合同单方面毁约。",
                "云飘过，光斑跑路，追不上。",
                "午睡地盘被太阳放了鸽子。",
            ],
            moodDelta: -0.05 ... -0.02,
            energyDelta: -0.04 ... -0.015,
            preferredHours: Set(10 ... 16)
        ),
        LocalGrowthTemplate(
            code: "cardboard_trap",
            textVariants: [
                "钻纸箱卡关，进退两难，尊严与体积谈判失败。",
                "纸壳口收得太紧，宇宙入口疑似虚假宣传。",
                "盒子征服战胜利在望，出口在另一维度。",
            ],
            moodDelta: -0.04 ... -0.01,
            energyDelta: -0.08 ... -0.04,
            preferredHours: nil
        ),
        LocalGrowthTemplate(
            code: "treat_rattle_tease",
            textVariants: [
                "零食罐晃出幻听，打开却是猫粮，情绪落差结算中。",
                "塑料响像开饭铃，结果只是人类手滑。",
                "嗅觉先涨停，实物延迟交割。",
            ],
            moodDelta: -0.07 ... -0.03,
            energyDelta: -0.05 ... -0.02,
            preferredHours: Set(17 ... 22)
        ),
        LocalGrowthTemplate(
            code: "rainy_window_mood",
            textVariants: [
                "雨点敲窗像打字，心情跟着节奏变灰阶。",
                "阴天滤镜全开，世界饱和度被没收。",
                "水痕在玻璃上画画，看久了有点惆怅。",
            ],
            moodDelta: -0.05 ... -0.02,
            energyDelta: -0.04 ... -0.015,
            preferredHours: nil
        ),
        LocalGrowthTemplate(
            code: "keyboard_warmth_hog",
            textVariants: [
                "键盘区温度诱人，趴太久腿麻，起身像拆机。",
                "F 键当枕头，醒来脸上印着使命。",
                "人体工学椅没轮到自己，委屈但不说。",
            ],
            moodDelta: -0.03 ... -0.01,
            energyDelta: -0.06 ... -0.025,
            preferredHours: Set(9 ... 23)
        ),
        LocalGrowthTemplate(
            code: "zoom_meeting_blep",
            textVariants: [
                "视频会议里人类点头如捣蒜，猫猫同步犯困。",
                "耳机里传来「对齐一下」，对齐到了睡眠区。",
                "摄像头灯常亮，明星包袱与电量一起掉。",
            ],
            moodDelta: -0.04 ... -0.015,
            energyDelta: -0.07 ... -0.03,
            preferredHours: Set(10 ... 18)
        ),
        LocalGrowthTemplate(
            code: "socks_thief",
            textVariants: [
                "袜子搬运工程超额，被人类当场退单。",
                "单只袜子的宇宙漂流计划被迫中止。",
                "战利品挂沙发边，证据太明显，社死现场。",
            ],
            moodDelta: -0.035 ... -0.01,
            energyDelta: -0.07 ... -0.03,
            preferredHours: nil
        ),
        LocalGrowthTemplate(
            code: "plant_leaf_interest",
            textVariants: [
                "对绿植叶子进行科研式嗅探，结果被喷壶误伤。",
                "土味与草味论文写到一半，实验对象后撤。",
                "光合作用旁观太久，自己光合作用不足。",
            ],
            moodDelta: -0.04 ... -0.01,
            energyDelta: -0.05 ... -0.02,
            preferredHours: Set(8 ... 19)
        ),
        LocalGrowthTemplate(
            code: "reflection_confusion",
            textVariants: [
                "黑屏反光里那只猫是谁？对峙三秒，CPU 过热。",
                "镜面平行宇宙发来挑衅，回应方式只有眨眼。",
                "倒影同步率 99%，仍觉得对方可疑。",
            ],
            moodDelta: -0.045 ... -0.015,
            energyDelta: -0.055 ... -0.02,
            preferredHours: nil
        ),
        LocalGrowthTemplate(
            code: "dream_running_legs",
            textVariants: [
                "梦里追猎物全速跑，醒来爪子在空气中结账。",
                "睡眠期腿部 DLC 更新过猛，清醒后补丁回滚。",
                "闭着眼马拉松，睁开眼欠费。",
            ],
            moodDelta: -0.03 ... -0.005,
            energyDelta: -0.11 ... -0.05,
            preferredHours: Set([0, 1, 2, 3, 4, 5])
        ),
        LocalGrowthTemplate(
            code: "icecube_paw",
            textVariants: [
                "好奇碰了冰块，爪爪撤回慢半拍，怀疑猫生。",
                "冷感突袭，神经写了个 bug report。",
                "水滴在爪垫上开趴，体验两极化。",
            ],
            moodDelta: -0.03 ... -0.01,
            energyDelta: -0.06 ... -0.025,
            preferredHours: Set(12 ... 20)
        ),
        LocalGrowthTemplate(
            code: "backup_snack_denied",
            textVariants: [
                "第二份小零食申请被驳回，听证会开在心里。",
                "卡路里预算像防盗门，猫猫没带钥匙。",
                "人类说「明天」，明天在猫猫字典里等于薛定谔。",
            ],
            moodDelta: -0.06 ... -0.025,
            energyDelta: -0.05 ... -0.02,
            preferredHours: Set(15 ... 23)
        ),
        LocalGrowthTemplate(
            code: "wifi_lag_angst",
            textVariants: [
                "网页转圈，猫猫以为地球自转卡帧。",
                "上传条不动，耐心条先动。",
                "信号格玩失踪，心情格跟着掉线。",
            ],
            moodDelta: -0.04 ... -0.015,
            energyDelta: -0.05 ... -0.02,
            preferredHours: Set(10 ... 23)
        ),
        LocalGrowthTemplate(
            code: "dust_mote_ballet",
            textVariants: [
                "阳光里灰尘跳芭蕾，头转太快脖子抗议。",
                "微粒群演太投入，观众席晕场。",
                "追光失败次数 +1，艺术细胞 -0.01。",
            ],
            moodDelta: -0.025 ... -0.005,
            energyDelta: -0.08 ... -0.035,
            preferredHours: Set(9 ... 16)
        ),
    ]

    /// 时段系数：用于与「事件密度」相乘
    static func periodMultiplier(forHour hour: Int) -> Double {
        switch hour {
        case 11 ... 14: return 1.35
        case 0 ... 2, 23: return 1.15
        case 13 ... 17: return 1.1
        default: return 1.0
        }
    }

    static func sampleEvent(at date: Date, calendar: Calendar = .current, rng: inout SplitMix64) -> PetDecayEventRecord? {
        let hour = calendar.component(.hour, from: date)
        let weightedBase: [(LocalGrowthTemplate, Double)] = templates.compactMap { t in
            if let pref = t.preferredHours {
                guard pref.contains(hour) else { return nil }
                return (t, 1.25)
            }
            return (t, 1.0)
        }
        let base = weightedBase.isEmpty ? templates.map { ($0, 1.0) } : weightedBase
        /// 权重微抖动：同一时刻多次抽样排序也会变，减少「怎么又是它」感
        let pool: [(LocalGrowthTemplate, Double)] = base.map { tpl, w in
            (tpl, w * (0.72 + 0.56 * rng.unitDouble()))
        }
        let total = pool.reduce(0.0) { $0 + $1.1 }
        var r = rng.unitDouble() * total
        for (tpl, w) in pool {
            r -= w
            if r <= 0 {
                return makeRecord(from: tpl, rng: &rng)
            }
        }
        return makeRecord(from: pool[0].0, rng: &rng)
    }

    private static func makeRecord(from tpl: LocalGrowthTemplate, rng: inout SplitMix64) -> PetDecayEventRecord {
        let variants = tpl.textVariants
        let idx = variants.isEmpty ? 0 : Int(rng.unitDouble() * Double(variants.count)) % variants.count
        let text = variants[idx]
        let md = rng.range(tpl.moodDelta)
        let ed = rng.range(tpl.energyDelta)
        return PetDecayEventRecord.make(
            reasonCode: tpl.code,
            reasonText: text,
            moodDelta: md,
            energyDelta: ed,
            source: .local,
            raw: nil
        )
    }
}

// MARK: - 轻量 PRNG（可复现、无额外依赖）

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unitDouble() -> Double {
        Double(next() >> 11) * (1.0 / Double(1 << 53))
    }

    mutating func range(_ r: ClosedRange<Double>) -> Double {
        let t = unitDouble()
        return r.lowerBound + (r.upperBound - r.lowerBound) * t
    }
}
