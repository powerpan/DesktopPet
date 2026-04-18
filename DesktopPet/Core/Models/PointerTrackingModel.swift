//
// PointerTrackingModel.swift
// 根据屏幕鼠标与宠物窗口的相对位置，输出轻量「注视」偏移（不改变状态机枚举，仅影响展示层）。
//

import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class PointerTrackingModel: ObservableObject {
    /// 水平注视偏移（pt），供 SwiftUI 做轻微平移
    @Published private(set) var gazeOffsetX: CGFloat = 0

    func updateGaze(mouseScreen: CGPoint, petFrame: CGRect?) {
        guard let petFrame else {
            gazeOffsetX = 0
            return
        }
        let center = CGPoint(x: petFrame.midX, y: petFrame.midY)
        let dx = mouseScreen.x - center.x
        let dy = mouseScreen.y - center.y
        let distance = hypot(dx, dy)
        let gazeRadius = PetConfig.petCanvasLayoutPoints * 1.25
        if distance > gazeRadius {
            gazeOffsetX = 0
            return
        }
        let maxOffset: CGFloat = 14
        let t = max(-1, min(1, dx / (PetConfig.petCanvasLayoutPoints * 0.59)))
        let verticalDamp = max(0.35, 1 - min(abs(dy), PetConfig.petCanvasLayoutPoints * 0.73) / PetConfig.petCanvasLayoutPoints)
        gazeOffsetX = -t * maxOffset * verticalDamp
    }
}
