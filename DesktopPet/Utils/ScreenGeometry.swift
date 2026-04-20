//
// ScreenGeometry.swift
// 屏幕几何工具：根据鼠标位置选取合适的可见桌面矩形，并把窗口原点限制在可见区内。
//

import AppKit
import CoreGraphics

/// 启用巡逻时，宠物随机落点所限制的显示器范围（菜单栏「DesktopPet」设置）。
enum PatrolRegionMode: String, CaseIterable, Identifiable, Codable {
    /// 仅在系统「主显示器」的可见桌面内巡逻（`NSScreen.screens` 首屏，与系统设置里标白条的显示器一致；不用 `NSScreen.main` 以免与菜单栏/焦点屏混淆）。
    case mainOnly = "main"
    /// 仅在外接等非主屏上巡逻；若无外接屏则退回主屏。
    case secondaryOnly = "secondary"
    /// 每次巡逻 tick 在已连接显示器中随机选一屏的可见区（主 + 副）。
    case mainAndSecondary = "all"
    /// 前台应用（排除本应用）主窗口中心落在哪块屏，就在该屏 `visibleFrame` 内巡逻；取不到前台窗时退回「含鼠标的屏」，再退回主屏。
    case focusScreen = "focus"

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .mainOnly: return "仅主屏"
        case .secondaryOnly: return "仅副屏"
        case .mainAndSecondary: return "主屏 + 副屏"
        case .focusScreen: return "焦点屏"
        }
    }
}

enum ScreenGeometry {
    /// 系统排列中的主显示器：`NSScreen.screens` 首项（Apple 文档中为 primary）；单屏时即该屏。
    static func systemPrimaryScreen(from screens: [NSScreen]) -> NSScreen {
        if let first = screens.first { return first }
        return NSScreen.main!
    }

    /// 返回「包含当前鼠标」的屏幕的 visibleFrame（排除菜单栏与 Dock）
    static func visibleFrameContainingMouse() -> CGRect {
        let mousePoint = NSEvent.mouseLocation
        let screens = NSScreen.screens
        // 多数情况下 mouse 落在 screen.frame 内
        if let screen = screens.first(where: { $0.frame.contains(mousePoint) }) {
            return screen.visibleFrame
        }
        // 菜单栏顶部等可能不在 frame 内但仍属于某屏 visibleFrame
        if let screen = screens.first(where: { $0.visibleFrame.contains(mousePoint) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame ?? .zero
    }

    /// 巡逻用：按设置选取一块「可见桌面」`visibleFrame`（不含菜单栏与 Dock）。
    static func visibleFrameForPatrol(mode: PatrolRegionMode) -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return .zero }
        let primary = systemPrimaryScreen(from: screens)
        let nonPrimary = screens.filter { $0 !== primary }

        switch mode {
        case .mainOnly:
            return primary.visibleFrame
        case .secondaryOnly:
            if let s = nonPrimary.randomElement() ?? nonPrimary.first {
                return s.visibleFrame
            }
            return primary.visibleFrame
        case .mainAndSecondary:
            return (screens.randomElement() ?? primary).visibleFrame
        case .focusScreen:
            let myPID = ProcessInfo.processInfo.processIdentifier
            if let front = approximateFrontmostAppWindowFrame(excludingPID: myPID),
               let screen = screenContainingWindowFrame(front, screens: screens) {
                return screen.visibleFrame
            }
            let mouseVF = visibleFrameContainingMouse()
            if !mouseVF.isEmpty { return mouseVF }
            return primary.visibleFrame
        }
    }

    /// 巡逻着陆点**调试遮罩**用：在「主屏 + 副屏 / 仅副屏」下若仍每次调用 `visibleFrameForPatrol`，会与定时刷新叠加导致 `visibleFrame` 在两块屏间随机切换、红框闪烁。
    /// 优先用 **宠物窗口** 与 `NSScreen.frame` 相交最大的那块屏的 `visibleFrame`；无窗口框时「主+副」退回含鼠标的屏，「仅副屏」退回第一块非主屏（顺序与 `NSScreen.screens` 一致）。
    static func patrolVisibleFrameForDebugOverlay(
        mode: PatrolRegionMode,
        petWindowFrame: CGRect?
    ) -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return .zero }
        let primary = systemPrimaryScreen(from: screens)
        let nonPrimary = screens.filter { $0 !== primary }

        switch mode {
        case .mainAndSecondary:
            if let pf = petWindowFrame, !pf.isEmpty,
               let s = screenContainingWindowFrame(pf, screens: screens) {
                return s.visibleFrame
            }
            let mouseVF = visibleFrameContainingMouse()
            if !mouseVF.isEmpty { return mouseVF }
            return primary.visibleFrame

        case .secondaryOnly:
            if let pf = petWindowFrame, !pf.isEmpty,
               let s = screenContainingWindowFrame(pf, screens: screens) {
                if nonPrimary.isEmpty { return s.visibleFrame }
                if nonPrimary.contains(where: { $0 === s }) {
                    return s.visibleFrame
                }
            }
            if let s = nonPrimary.first {
                return s.visibleFrame
            }
            return primary.visibleFrame

        case .mainOnly, .focusScreen:
            return visibleFrameForPatrol(mode: mode)
        }
    }

    /// Quartz / AppKit 全局坐标下，用窗口外框与哪块 `NSScreen.frame` 相交面积最大判定归属屏；无相交则用中心点落在的屏。
    private static func screenContainingWindowFrame(_ windowFrame: CGRect, screens: [NSScreen]) -> NSScreen? {
        guard !screens.isEmpty else { return nil }
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for s in screens {
            let inter = windowFrame.intersection(s.frame)
            let a = max(0, inter.width) * max(0, inter.height)
            if a > bestArea {
                bestArea = a
                best = s
            }
        }
        if let best, bestArea > 0 { return best }
        let c = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return screens.first { $0.frame.contains(c) }
    }

    static func clampedPoint(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }

    /// 巡逻用：在 `visibleFrame` 内对窗口**原点**做**均匀随机**（四边留 `margin`）。若提供 `lastOrigin`，会尽量在 `minDistanceFromLast` 以外重采样若干次，减轻「总在同一小块区域打转」；退化时退回 `clampedOrigin` 的几何中心附近。
    static func randomPatrolWindowOrigin(
        windowSize: CGSize,
        in visibleFrame: CGRect,
        margin: CGFloat,
        lastOrigin: CGPoint?,
        minDistanceFromLast: CGFloat,
        maxResamples: Int = 14
    ) -> CGPoint {
        let minX = visibleFrame.minX + margin
        let minY = visibleFrame.minY + margin
        let maxX = visibleFrame.maxX - windowSize.width - margin
        let maxY = visibleFrame.maxY - windowSize.height - margin
        if maxX < minX || maxY < minY {
            return clampedOrigin(
                windowSize,
                origin: CGPoint(x: visibleFrame.midX - windowSize.width / 2, y: visibleFrame.midY - windowSize.height / 2),
                in: visibleFrame,
                margin: margin
            )
        }
        func sample() -> CGPoint {
            CGPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
        }
        if let last = lastOrigin {
            for _ in 0..<maxResamples {
                let p = sample()
                if hypot(p.x - last.x, p.y - last.y) >= minDistanceFromLast {
                    return p
                }
            }
        }
        return sample()
    }

    /// 巡逻用：在 `region` 与 `visibleFrame`（含 `margin`）的合法原点域的交集中，对窗口**左下角原点**均匀随机，使宠物矩形完全落在 `region` 内；退化时退回 `region` 中心附近再夹紧。
    static func randomPatrolWindowOriginInsideRect(
        windowSize: CGSize,
        inside region: CGRect,
        in visibleFrame: CGRect,
        margin: CGFloat,
        lastOrigin: CGPoint?,
        minDistanceFromLast: CGFloat,
        maxResamples: Int = 14
    ) -> CGPoint {
        let legMinX = visibleFrame.minX + margin
        let legMinY = visibleFrame.minY + margin
        let legMaxX = visibleFrame.maxX - windowSize.width - margin
        let legMaxY = visibleFrame.maxY - windowSize.height - margin
        let ix0 = max(legMinX, region.minX)
        let iy0 = max(legMinY, region.minY)
        let ix1 = min(legMaxX, region.maxX - windowSize.width)
        let iy1 = min(legMaxY, region.maxY - windowSize.height)
        if ix1 < ix0 || iy1 < iy0 {
            return clampedOrigin(
                windowSize,
                origin: CGPoint(x: region.midX - windowSize.width / 2, y: region.midY - windowSize.height / 2),
                in: visibleFrame,
                margin: margin
            )
        }
        func sample() -> CGPoint {
            CGPoint(x: CGFloat.random(in: ix0...ix1), y: CGFloat.random(in: iy0...iy1))
        }
        if let last = lastOrigin {
            for _ in 0..<maxResamples {
                let p = sample()
                if hypot(p.x - last.x, p.y - last.y) >= minDistanceFromLast {
                    return p
                }
            }
        }
        return sample()
    }

    /// 巡逻用：在合法矩形内随机采样，使宠物窗口矩形与 `obstacle` **不相交**（可选安全间隙 `clearance`）；尽量满足与 `lastOrigin` 的距离。
    /// - `allowPartialFallback` 为 `false` 时（如刻度 0）**绝不**退回「落在障碍内」的采样；会走网格/角点与额外随机尝试。
    static func randomPatrolWindowOriginOutsideFrontRect(
        windowSize: CGSize,
        in visibleFrame: CGRect,
        margin: CGFloat,
        lastOrigin: CGPoint?,
        minDistanceFromLast: CGFloat,
        obstacle: CGRect,
        clearance: CGFloat = 8,
        maxAttempts: Int = 96,
        allowPartialFallback: Bool = true
    ) -> CGPoint {
        let minX = visibleFrame.minX + margin
        let minY = visibleFrame.minY + margin
        let maxX = visibleFrame.maxX - windowSize.width - margin
        let maxY = visibleFrame.maxY - windowSize.height - margin
        if maxX < minX || maxY < minY {
            return randomPatrolWindowOrigin(
                windowSize: windowSize,
                in: visibleFrame,
                margin: margin,
                lastOrigin: lastOrigin,
                minDistanceFromLast: minDistanceFromLast
            )
        }
        let block = obstacle.insetBy(dx: -clearance, dy: -clearance)
        func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let r = a.intersection(b)
            if r.isNull || r.isEmpty { return 0 }
            return max(0, r.width) * max(0, r.height)
        }
        func sample() -> CGPoint {
            CGPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
        }

        var clearOfFront: [CGPoint] = []
        var bestPartialArea: CGFloat = .greatestFiniteMagnitude
        var bestPartialOrigin: CGPoint?

        let attempts = allowPartialFallback ? maxAttempts : max(maxAttempts, 160)
        for _ in 0..<attempts {
            let oc = clampedOrigin(windowSize, origin: sample(), in: visibleFrame, margin: margin)
            let pr = CGRect(origin: oc, size: windowSize)
            let a = intersectionArea(pr, block)
            if !pr.intersects(block) {
                clearOfFront.append(oc)
            } else if allowPartialFallback, a < bestPartialArea {
                bestPartialArea = a
                bestPartialOrigin = oc
            }
        }

        if !clearOfFront.isEmpty {
            if let last = lastOrigin {
                let withDistance = clearOfFront.filter { hypot($0.x - last.x, $0.y - last.y) >= minDistanceFromLast }
                if let pick = withDistance.randomElement() {
                    return pick
                }
                if let pick = clearOfFront.max(by: {
                    hypot($0.x - last.x, $0.y - last.y) < hypot($1.x - last.x, $1.y - last.y)
                }) {
                    return pick
                }
            }
            return clearOfFront.randomElement()!
        }

        if !allowPartialFallback {
            if let g = patrolGridOriginOutsideObstacle(
                windowSize: windowSize,
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY,
                obstacle: obstacle,
                clearance: clearance,
                lastOrigin: lastOrigin,
                minDistanceFromLast: minDistanceFromLast
            ) {
                return g
            }
            if let c = patrolCornerOriginsOutsideObstacle(
                windowSize: windowSize,
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY,
                obstacle: obstacle,
                clearance: clearance
            ).randomElement() {
                return c
            }
            for _ in 0..<480 {
                let oc = clampedOrigin(windowSize, origin: sample(), in: visibleFrame, margin: margin)
                let pr = CGRect(origin: oc, size: windowSize)
                if !pr.intersects(block) {
                    return oc
                }
            }
        }

        if allowPartialFallback, let partial = bestPartialOrigin {
            return partial
        }
        return randomPatrolWindowOrigin(
            windowSize: windowSize,
            in: visibleFrame,
            margin: margin,
            lastOrigin: lastOrigin,
            minDistanceFromLast: minDistanceFromLast
        )
    }

    /// 若宠物矩形（含 `clearance` 膨胀后的障碍）仍与障碍相交，则在合法矩形内搜索一个不相交的合法原点；用于混合/插值后的兜底。
    static func patrolClampOriginClearOfObstacle(
        windowSize: CGSize,
        origin: CGPoint,
        in visibleFrame: CGRect,
        margin: CGFloat,
        obstacle: CGRect,
        clearance: CGFloat = 8
    ) -> CGPoint {
        let minX = visibleFrame.minX + margin
        let minY = visibleFrame.minY + margin
        let maxX = visibleFrame.maxX - windowSize.width - margin
        let maxY = visibleFrame.maxY - windowSize.height - margin
        let block = obstacle.insetBy(dx: -clearance, dy: -clearance)
        var o = clampedOrigin(windowSize, origin: origin, in: visibleFrame, margin: margin)
        let pet0 = CGRect(origin: o, size: windowSize)
        if maxX < minX || maxY < minY || !pet0.intersects(block) {
            return o
        }
        if let g = patrolGridOriginOutsideObstacle(
            windowSize: windowSize,
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            obstacle: obstacle,
            clearance: clearance,
            lastOrigin: nil,
            minDistanceFromLast: 0
        ) {
            return g
        }
        for _ in 0..<200 {
            let p = CGPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
            let oc = clampedOrigin(windowSize, origin: p, in: visibleFrame, margin: margin)
            let pet = CGRect(origin: oc, size: windowSize)
            if !pet.intersects(block) {
                return oc
            }
        }
        if let c = patrolCornerOriginsOutsideObstacle(
            windowSize: windowSize,
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            obstacle: obstacle,
            clearance: clearance
        ).randomElement() {
            return c
        }
        return o
    }

    /// 当前系统前台应用（排除桌宠）在 `patrolVisibleFrame` 内所有 layer-0 可见窗口的并集（裁剪到巡逻区），用于副屏/焦点屏避障。
    static func patrolObstacleUnionFrontmostAppOnVisibleFrame(patrolVisibleFrame: CGRect, excludingPID: pid_t) -> CGRect? {
        guard !patrolVisibleFrame.isEmpty,
              let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != excludingPID
        else { return nil }
        let fpid = pid_t(frontApp.processIdentifier)
        return patrolWindowUnionForOwnerPID(
            fpid,
            patrolVisibleFrame: patrolVisibleFrame,
            excludingPID: excludingPID,
            minWidth: 32,
            minHeight: 32
        )
    }

    /// 巡逻障碍：优先「前台应用在本屏可见区内的所有窗口」并集；若为空（例如前台仅在另一块屏）则退回 z 序首个与巡逻区相交的大窗裁剪矩形。
    static func patrolObstacleForAvoidance(patrolVisibleFrame: CGRect, excludingPID: pid_t) -> CGRect? {
        if let u = patrolObstacleUnionFrontmostAppOnVisibleFrame(patrolVisibleFrame: patrolVisibleFrame, excludingPID: excludingPID) {
            return u
        }
        if let fg = approximateFrontmostAppWindowFrameIntersecting(patrolVisibleFrame: patrolVisibleFrame, excludingPID: excludingPID)
            ?? approximateFrontmostAppWindowFrame(excludingPID: excludingPID) {
            return patrolClippedFrontRect(globalFront: fg, patrolVisibleFrame: patrolVisibleFrame)
        }
        return nil
    }

    /// `kCGWindowBounds` 按 Apple 文档为 **主显示器左上角为原点、Y 向下** 的屏幕空间；`NSScreen.frame` / `visibleFrame` 为 **左下角原点、Y 向上**。
    /// 与 AppKit 对齐：`origin.y = menuBarScreen.maxY - cgY - height`，`origin.x` 与 Quartz 一致。此前误当全局左下角坐标会与 `visibleFrame` 求交后只剩底部条带（像 Dock 区）。
    private static func cgKCGWindowBoundsToAppKitGlobal(_ raw: CGRect) -> CGRect {
        let r = raw.standardized
        guard let menu = NSScreen.main ?? NSScreen.screens.first else { return r }
        let mf = menu.frame
        let yApp = mf.minY + mf.height - r.minY - r.height
        return CGRect(x: r.minX, y: yApp, width: r.width, height: r.height).standardized
    }

    private static func patrolWindowUnionForOwnerPID(
        _ ownerPID: pid_t,
        patrolVisibleFrame: CGRect,
        excludingPID: pid_t,
        minWidth: CGFloat,
        minHeight: CGFloat
    ) -> CGRect? {
        guard ownerPID != excludingPID else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var unioned: CGRect?
        for entry in info {
            let pid = pid_t((entry["kCGWindowOwnerPID"] as? NSNumber)?.int32Value ?? 0)
            if pid != ownerPID || pid == excludingPID { continue }
            let layer = (entry["kCGWindowLayer"] as? NSNumber)?.intValue ?? 0
            if layer != 0 { continue }
            if let alphaNum = entry["kCGWindowAlpha"] as? NSNumber, alphaNum.doubleValue < 0.05 {
                continue
            }
            guard let boundsDict = entry["kCGWindowBounds"] as? [String: Any] else { continue }
            let x = (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0
            let w = (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0
            let h = (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0
            let rect = cgKCGWindowBoundsToAppKitGlobal(CGRect(x: x, y: y, width: w, height: h))
            if w < minWidth || h < minHeight { continue }
            if rect.isEmpty || rect.isInfinite || rect.isNull { continue }
            if !rect.intersects(patrolVisibleFrame) { continue }
            let clip = rect.intersection(patrolVisibleFrame).standardized
            if clip.width < 4 || clip.height < 4 { continue }
            unioned = unioned.map { $0.union(clip) } ?? clip
        }
        return unioned?.standardized
    }

    private static func patrolGridOriginOutsideObstacle(
        windowSize: CGSize,
        minX: CGFloat,
        minY: CGFloat,
        maxX: CGFloat,
        maxY: CGFloat,
        obstacle: CGRect,
        clearance: CGFloat,
        lastOrigin: CGPoint?,
        minDistanceFromLast: CGFloat
    ) -> CGPoint? {
        let block = obstacle.insetBy(dx: -clearance, dy: -clearance)
        let gx = 22
        let gy = 18
        for iy in 0...gy {
            for ix in 0...gx {
                let tx = CGFloat(ix) / CGFloat(gx)
                let ty = CGFloat(iy) / CGFloat(gy)
                let ox = minX + (maxX - minX) * tx
                let oy = minY + (maxY - minY) * ty
                let pet = CGRect(origin: CGPoint(x: ox, y: oy), size: windowSize)
                if pet.intersects(block) { continue }
                if let last = lastOrigin, hypot(ox - last.x, oy - last.y) < minDistanceFromLast * 0.45 { continue }
                return CGPoint(x: ox, y: oy)
            }
        }
        return nil
    }

    private static func patrolCornerOriginsOutsideObstacle(
        windowSize: CGSize,
        minX: CGFloat,
        minY: CGFloat,
        maxX: CGFloat,
        maxY: CGFloat,
        obstacle: CGRect,
        clearance: CGFloat
    ) -> [CGPoint] {
        let block = obstacle.insetBy(dx: -clearance, dy: -clearance)
        let pts: [CGPoint] = [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: maxY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: (minX + maxX) / 2, y: minY),
            CGPoint(x: (minX + maxX) / 2, y: maxY),
            CGPoint(x: minX, y: (minY + maxY) / 2),
            CGPoint(x: maxX, y: (minY + maxY) / 2)
        ]
        return pts.shuffled().filter { pt in
            !CGRect(origin: pt, size: windowSize).intersects(block)
        }
    }

    /// AppKit 窗口坐标：原点在左下角，将 origin 限制在 visibleFrame 内并留边距
    static func clampedOrigin(_ windowSize: CGSize, origin: CGPoint, in visibleFrame: CGRect, margin: CGFloat) -> CGPoint {
        let minX = visibleFrame.minX + margin
        let minY = visibleFrame.minY + margin
        let maxX = visibleFrame.maxX - windowSize.width - margin
        let maxY = visibleFrame.maxY - windowSize.height - margin
        if maxX < minX || maxY < minY {
            return CGPoint(x: minX, y: minY)
        }
        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    /// 尝试取「前台其他应用」的主窗口外框（Quartz 屏幕坐标，与 `NSWindow.frame` / `NSEvent.mouseLocation` 一致）。
    /// 用于巡逻时偶尔贴近活动窗口顶部；若系统未返回可用数据则返回 nil。
    static func approximateFrontmostAppWindowFrame(excludingPID: pid_t) -> CGRect? {
        frontmostAppWindowFrameFromWindowList(excludingPID: excludingPID, intersecting: nil)
    }

    /// 与 `approximateFrontmostAppWindowFrame` 相同筛选，但要求窗口矩形与 `patrolVisibleFrame` **相交**（按 z 序取第一个命中）。
    /// 多屏时全局最前窗常在主屏，副屏/焦点屏巡逻应优先用本函数，否则 `visibleFrame` 与主屏窗不相交会导致避窗、贴沿逻辑整段被跳过。
    static func approximateFrontmostAppWindowFrameIntersecting(patrolVisibleFrame: CGRect, excludingPID: pid_t) -> CGRect? {
        guard !patrolVisibleFrame.isEmpty else { return nil }
        return frontmostAppWindowFrameFromWindowList(excludingPID: excludingPID, intersecting: patrolVisibleFrame)
    }

    /// 全局前台窗外框限制在当前巡逻 `visibleFrame` 内的部分；用于避窗与贴沿，避免跨屏外框在副屏上误判为「不相交」。
    static func patrolClippedFrontRect(globalFront: CGRect, patrolVisibleFrame: CGRect) -> CGRect? {
        guard !patrolVisibleFrame.isEmpty else { return nil }
        let r = globalFront.intersection(patrolVisibleFrame)
        guard !r.isNull, !r.isEmpty else { return nil }
        let s = r.standardized
        guard s.width >= 4, s.height >= 4 else { return nil }
        return s
    }

    private static func frontmostAppWindowFrameFromWindowList(excludingPID: pid_t, intersecting patrolVisibleFrame: CGRect?) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in info {
            let ownerPID = pid_t((entry["kCGWindowOwnerPID"] as? NSNumber)?.int32Value ?? 0)
            if ownerPID == excludingPID { continue }

            let layer = (entry["kCGWindowLayer"] as? NSNumber)?.intValue ?? 0
            if layer != 0 { continue }

            if let alphaNum = entry["kCGWindowAlpha"] as? NSNumber, alphaNum.doubleValue < 0.05 {
                continue
            }

            guard let boundsDict = entry["kCGWindowBounds"] as? [String: Any] else {
                continue
            }
            let x = (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0
            let w = (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0
            let h = (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0
            let rect = cgKCGWindowBoundsToAppKitGlobal(CGRect(x: x, y: y, width: w, height: h))
            if w < 180 || h < 120 { continue }
            if rect.isEmpty || rect.isInfinite || rect.isNull { continue }
            if let vf = patrolVisibleFrame, !rect.intersects(vf) { continue }
            return rect
        }
        return nil
    }
}
