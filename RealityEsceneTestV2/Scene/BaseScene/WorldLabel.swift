// WorldLabel.swift
// RealityEsceneTestV2
//
// Floating labels that live in the scene rather than on the HUD.
//
// TextComponent draws an attributed string onto a canvas mesh in world space,
// and BillboardComponent keeps that canvas turned towards the camera. Together
// they let the demo caption itself: the recording shows "512 RIGID BODIES"
// hanging over the actual 512 bodies, which reads far better on camera than a
// number in a corner panel that the viewer has to go looking for.
//
// TextComponent sizes its canvas in points, where a point is 1/72 inch — about
// 0.35 mm of world space. A readable label therefore needs a canvas measured
// in the low thousands of points and a font to match; the entity's scale then
// brings it to the size the scene wants.

import RealityKit
import AppKit

@MainActor
func makeWorldLabel(
    _ text: String,
    subtitle: String? = nil,
    at position: SIMD3<Float>,
    tint: NSColor = .white,
    width: CGFloat = 2600
) -> Entity {

    let label = Entity()
    label.name = "worldLabel"
    label.position = position

    // Styled as an NSAttributedString and converted. Writing an NSFont into
    // an AttributeContainer instead warns about NSFont not being Sendable,
    // even though this whole function is main-actor isolated.
    let styled = NSMutableAttributedString(
        string: text,
        attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 190, weight: .bold),
            .foregroundColor: tint
        ]
    )

    if let subtitle {
        styled.append(NSAttributedString(
            string: "\n" + subtitle,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 120, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.6)
            ]
        ))
    }

    let attributed = AttributedString(styled)

    var textComponent = TextComponent()
    textComponent.text = attributed
    textComponent.size = CGSize(width: width, height: subtitle == nil ? 300 : 560)
    textComponent.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
    textComponent.cornerRadius = 60
    textComponent.edgeInsets = NSEdgeInsets(top: 40, left: 60, bottom: 40, right: 60)
    label.components.set(textComponent)

    // Always facing the camera, so the caption is readable from anywhere in
    // the arena instead of only from where the shot was framed.
    label.components.set(BillboardComponent())

    // A canvas point is about 0.35 mm of world space, so the raw canvas comes
    // out barely a metre across and unreadable from the far side of the arena.
    // This brings it to roughly four metres wide.
    label.scale = .init(repeating: 4.5)

    return label
}
