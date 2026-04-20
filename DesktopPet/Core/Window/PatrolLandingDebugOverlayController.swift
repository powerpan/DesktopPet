//
// PatrolLandingDebugOverlayController.swift
// 测试用：在「贴近前台窗」为 0 且开关打开时，用半透明遮罩标出巡逻 visibleFrame、宠物可覆盖区、原点范围与避障矩形。
//

import AppKit
import Foundation

struct PatrolLandingDebugSnapshot {
    let visibleFrame: CGRect
    let petCoverageRect: CGRect
    let originExtentsRect: CGRect
    let obstacle: CGRect?

    static func build(
        patrolRegionMode: PatrolRegionMode,
        patrolEdgeMargin: Double,
        petScale: Double,
        lastPatrolVisibleFrame: CGRect?,
        petWindowFrame: CGRect?,
        excludingPID: pid_t
    ) -> PatrolLandingDebugSnapshot? {
        let vf: CGRect
        switch patrolRegionMode {
        case .mainAndSecondary, .secondaryOnly:
            if let o = lastPatrolVisibleFrame, !o.isEmpty {
                vf = o
            } else {
                vf = ScreenGeometry.patrolVisibleFrameForDebugOverlay(
                    mode: patrolRegionMode,
                    petWindowFrame: petWindowFrame
                )
            }
        default:
            vf = ScreenGeometry.patrolVisibleFrameForDebugOverlay(
                mode: patrolRegionMode,
                petWindowFrame: petWindowFrame
            )
        }
        if vf.isEmpty { return nil }
        let margin = CGFloat(
            min(max(patrolEdgeMargin, PetConfig.patrolEdgeMarginMin), PetConfig.patrolEdgeMarginMax)
        )
        let side = petWindowFrame.map { max($0.width, $0.height) }
            ?? CGFloat(PetConfig.exteriorHitSide(scale: petScale))
        let sz = CGSize(width: side, height: side)
        let minX = vf.minX + margin
        let minY = vf.minY + margin
        let maxX = vf.maxX - sz.width - margin
        let maxY = vf.maxY - sz.height - margin
        let petCoverage = CGRect(
            x: vf.minX + margin,
            y: vf.minY + margin,
            width: max(0, vf.maxX - vf.minX - 2 * margin),
            height: max(0, vf.maxY - vf.minY - 2 * margin)
        )
        let originExtents: CGRect
        if maxX >= minX, maxY >= minY {
            originExtents = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } else {
            originExtents = .zero
        }
        let obstacle = ScreenGeometry.patrolObstacleForAvoidance(patrolVisibleFrame: vf, excludingPID: excludingPID)
        return PatrolLandingDebugSnapshot(
            visibleFrame: vf,
            petCoverageRect: petCoverage,
            originExtentsRect: originExtents,
            obstacle: obstacle
        )
    }
}

private final class PatrolLandingDebugDrawView: NSView {
    var screenFrameInGlobal: CGRect = .zero
    var snapshot: PatrolLandingDebugSnapshot?

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        guard let snap = snapshot else { return }

        func local(_ g: CGRect) -> CGRect {
            CGRect(
                x: g.minX - screenFrameInGlobal.minX,
                y: g.minY - screenFrameInGlobal.minY,
                width: g.width,
                height: g.height
            )
        }

        let vis = local(snap.visibleFrame)
        NSColor.systemBlue.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: vis).fill()
        NSColor.systemBlue.withAlphaComponent(0.55).setStroke()
        let pVis = NSBezierPath(rect: vis)
        pVis.lineWidth = 1.5
        pVis.stroke()

        let cov = local(snap.petCoverageRect)
        if cov.width > 0, cov.height > 0 {
            NSColor.systemGreen.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: cov).fill()
            NSColor.systemGreen.withAlphaComponent(0.5).setStroke()
            let pCov = NSBezierPath(rect: cov)
            pCov.lineWidth = 1.2
            pCov.stroke()
        }

        let ori = local(snap.originExtentsRect)
        if ori.width > 1, ori.height > 1 {
            NSColor.systemOrange.withAlphaComponent(0.85).setStroke()
            let dash: [CGFloat] = [6, 4]
            let pOri = NSBezierPath(rect: ori)
            pOri.lineWidth = 2
            pOri.setLineDash(dash, count: 2, phase: 0)
            pOri.stroke()
        }

        if let obs = snap.obstacle {
            let o = local(obs)
            NSColor.systemRed.withAlphaComponent(0.22).setFill()
            NSBezierPath(rect: o).fill()
            NSColor.systemRed.withAlphaComponent(0.75).setStroke()
            let pO = NSBezierPath(rect: o)
            pO.lineWidth = 2
            pO.stroke()
        }

        let label = "DesktopPet 巡逻落点预览（测试）"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.9)
        ]
        (label as NSString).draw(
            with: NSRect(x: 10, y: bounds.maxY - 28, width: bounds.width - 20, height: 22),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
    }
}

@MainActor
final class PatrolLandingDebugOverlayController {
    private var windows: [NSWindow] = []

    func hide() {
        for w in windows {
            w.orderOut(nil)
        }
        windows.removeAll()
    }

    func update(snapshot: PatrolLandingDebugSnapshot) {
        let screens = NSScreen.screens
        if windows.count != screens.count {
            hide()
            for screen in screens {
                let frame = screen.frame
                let w = NSWindow(
                    contentRect: frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                w.isOpaque = false
                w.backgroundColor = .clear
                w.level = .floating
                w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                w.isReleasedWhenClosed = false
                w.ignoresMouseEvents = true
                w.hasShadow = false
                w.setFrame(frame, display: false)
                let v = PatrolLandingDebugDrawView(frame: CGRect(origin: .zero, size: frame.size))
                v.autoresizingMask = [.width, .height]
                w.contentView = v
                windows.append(w)
            }
        }
        for (i, screen) in screens.enumerated() where i < windows.count {
            let w = windows[i]
            let frame = screen.frame
            w.setFrame(frame, display: true)
            guard let v = w.contentView as? PatrolLandingDebugDrawView else { continue }
            v.frame = CGRect(origin: .zero, size: frame.size)
            v.screenFrameInGlobal = frame
            v.snapshot = snapshot
            v.needsDisplay = true
            w.orderFrontRegardless()
        }
    }
}
