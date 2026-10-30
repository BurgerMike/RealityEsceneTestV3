//
//  DisplayLinkView.swift
//  RealityEsceneTest
//
//  Created by Miguel Carlos Elizondo Martinez on 25/05/26.
//

import SwiftUI
import AppKit

struct DisplayLinkView: NSViewRepresentable {
    let gameLoop: GameLoop

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        gameLoop.start(in: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
