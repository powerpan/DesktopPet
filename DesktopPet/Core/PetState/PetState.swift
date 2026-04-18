//
// PetState.swift
// 宠物展示用状态枚举（待机、走、敲击、跳、睡），与状态机及占位动画文案对应。
//

enum PetState: String {
    case idle
    case walk
    case keyTap
    case jump
    case sleep
}
