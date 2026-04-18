//
// DeskMirrorKeyImage.swift
// 从 Bundle 的 DeskMirror（cover / nohand_cover、left-keys、right-keys）加载 PNG；命名与 BongoCat keyboard/resources 一致。
// 底图与爪印、方向图应为同一像素尺寸，叠放时同比例缩放即可对齐。
// 分发前请自行确认第三方素材许可。
//

import AppKit

enum DeskMirrorKeyImage {
    /// 用于整幅叠放区域的宽高比（优先当前选用的底图）。
    static func deskMirrorArtAspectRatio(inputActive: Bool) -> CGFloat {
        if let img = deskMirrorCoverImage(inputActive: inputActive), img.size.height > 0 {
            return img.size.width / img.size.height
        }
        if let sample = leftKeyImage(forKeyCode: 12), sample.size.height > 0 {
            return sample.size.width / sample.size.height
        }
        return 2.0
    }

    /// 空闲用 `cover.png`；有键盘按下或鼠标方向时用 `nohand_cover.png`（便于叠爪印层）。
    static func deskMirrorCoverImage(inputActive: Bool) -> NSImage? {
        let primary = inputActive ? "nohand_cover" : "cover"
        let fallback = inputActive ? "cover" : "nohand_cover"
        if let img = nsImage(stem: primary, subdirectory: "DeskMirror") {
            return img
        }
        return nsImage(stem: fallback, subdirectory: "DeskMirror")
    }

    private static func pngURL(stem: String, subdirectory: String) -> URL? {
        Bundle.main.url(forResource: stem, withExtension: "png", subdirectory: subdirectory)
    }

    static func nsImage(stem: String, subdirectory: String) -> NSImage? {
        guard let url = pngURL(stem: stem, subdirectory: subdirectory) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// `NSEvent.keyCode` → `left-keys` 文件名（不含 .png），与 `PhysicalKeyLayout.keyboardRows` 一致。
    static func leftKeyStem(forKeyCode code: UInt16) -> String? {
        switch code {
        case 18 ... 26:
            return "Num\(code - 17)"
        case 29:
            return "Num0"
        case 12: return "KeyQ"
        case 13: return "KeyW"
        case 14: return "KeyE"
        case 15: return "KeyR"
        case 17: return "KeyT"
        case 16: return "KeyY"
        case 32: return "KeyU"
        case 34: return "KeyI"
        case 31: return "KeyO"
        case 35: return "KeyP"
        case 0: return "KeyA"
        case 1: return "KeyS"
        case 2: return "KeyD"
        case 3: return "KeyF"
        case 5: return "KeyG"
        case 4: return "KeyH"
        case 38: return "KeyJ"
        case 40: return "KeyK"
        case 37: return "KeyL"
        case 6: return "KeyZ"
        case 7: return "KeyX"
        case 8: return "KeyC"
        case 9: return "KeyV"
        case 11: return "KeyB"
        case 45: return "KeyN"
        case 46: return "KeyM"
        default:
            return nil
        }
    }

    static func leftKeyImage(forKeyCode code: UInt16) -> NSImage? {
        guard let stem = leftKeyStem(forKeyCode: code) else { return nil }
        return nsImage(stem: stem, subdirectory: "DeskMirror/left-keys")
    }

    static func mouseStem(for direction: DeskMouseMirrorDirection) -> String? {
        switch direction {
        case .none: return nil
        case .up: return "UpArrow"
        case .down: return "DownArrow"
        case .left: return "LeftArrow"
        case .right: return "RightArrow"
        }
    }

    static func mouseImage(for direction: DeskMouseMirrorDirection) -> NSImage? {
        guard let stem = mouseStem(for: direction) else { return nil }
        return nsImage(stem: stem, subdirectory: "DeskMirror/right-keys")
    }
}
