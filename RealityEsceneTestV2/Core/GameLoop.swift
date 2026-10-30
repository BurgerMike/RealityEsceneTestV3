//
//  GameLoop.swift
//  RealityEsceneTest
//
//  Created by Miguel Carlos Elizondo Martinez on 25/05/26.
//

import AppKit
import QuartzCore

@MainActor
final class GameLoop {
    private var displayLink: CADisplayLink?
    var onFrame: ((Double) -> Void)?

    func start(in view: NSView) {
        // DisplayLinkTarget recibe el timestamp y lo pasa al closure
        let target = DisplayLinkTarget { [weak self] timestamp in
            self?.onFrame?(timestamp)
        }
        displayLink = view.displayLink(target: target, selector: #selector(DisplayLinkTarget.frame))
        updateFrameRate()
        displayLink?.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateFrameRate() {
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30,
            maximum: 120,   // techo — ProMotion máximo
            preferred: 0    // 0 = nativo de la pantalla, no forzado
        )
    }
}

// Target separado para evitar conflicto @MainActor + @objc
// El selector no puede vivir en una clase @MainActor — va aquí
private final class DisplayLinkTarget: NSObject {
    let callback: (Double) -> Void
    init(_ callback: @escaping (Double) -> Void) {
        self.callback = callback
    }
    @objc func frame(_ link: CADisplayLink) {
        callback(link.timestamp)
    }
}

