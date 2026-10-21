import SwiftUI
import ZivletWheelCore

/// The wheel: backdrop disk, petals (Liquid Glass or Solid), hub label and status pill. Highlight is model-driven
/// because hover never reaches us during an external drag (14 §2.3).
public struct WheelView: View {
    let store: WheelStore
    @Namespace private var glassSpace
    @Environment(\.colorScheme) private var colorScheme
    /// Solid-theme hairline so the disk edge shows over dark windows.
    private static let solidRim = Color(white: 1, opacity: 0.16)

    public init(store: WheelStore) { self.store = store }

    public var body: some View {
        ZStack {
            if let model = store.model {
                petals(model)
                    .scaleEffect(store.isExpanded || store.appearance.reduceMotion ? 1 : WheelTiming.introScale)
                    .opacity(store.isExpanded ? 1 : 0)
                    .modifier(ShakeEffect(animatableData: Double(store.rejectCount)))
                HubLabelView(text: model.hubLabel, compact: model.hubIsCompact, colour: hubColour)
                if let text = store.pillText { StatusPill(text: text, theme: store.theme) }
            }
        }
        .frame(width: WheelLayout.geometry.panelSide, height: WheelLayout.geometry.panelSide)
        .animation(introAnimation, value: store.isExpanded)
        .animation(motion(.snappy(duration: WheelTiming.highlight)), value: store.model?.highlighted)
        .animation(modeSwitch, value: store.model?.mode)
        .animation(.linear(duration: WheelTiming.shake), value: store.rejectCount)
        // Runs after the update that rendered the collapsed wheel, and is cancelled when a new one is presented.
        .task(id: store.presentation) { [store, presentation = store.presentation] in
            store.expandIfPending(presentation)
        }
    }

    @ViewBuilder private func petals(_ model: WheelModel) -> some View {
        let g = WheelLayout.geometry
        let disk = RingShape(inner: g.hubRadius, outer: g.ringOuter)
        // The hub is a r 42.24 disc, so its label never sits on whatever is behind the panel.
        let hub = Circle().inset(by: g.panelSide / 2 - g.hubRadius)
        let rim = Circle().inset(by: g.panelSide / 2 - g.ringOuter)
        switch store.theme {
        case .glass:
            ZStack {
                DiskShadow(radius: g.ringOuter)
                Color.clear.glassEffect(.clear, in: disk)
                hub.fill(GlassInk.idleScrim(for: colorScheme)).glassEffect(.regular, in: hub)
                GlassEffectContainer(spacing: 6) {
                    ZStack { ForEach(Array(model.slices.enumerated()), id: \.element.id) { glassPetal($1, $0, model) } }
                }
            }
        case .solid:
            ZStack {
                DiskShadow(radius: g.ringOuter)
                disk.fill(Color(white: 0.08))
                rim.strokeBorder(Self.solidRim, lineWidth: 1)
                hub.fill(Color(white: 0.08))
                ForEach(Array(model.slices.enumerated()), id: \.element.id) { solidPetal($1, $0, model) }
            }
        }
    }

    private func glassPetal(_ slice: WheelSlice, _ index: Int, _ model: WheelModel) -> some View {
        let hot = model.highlighted == index
        let shape = PetalShape(slot: index, count: model.slices.count, grow: hot ? 1.05 : 1)
        let palette = store.appearance.palette
        return label(slice, index, model, colour: hot ? palette.labelOnAccent.color : .primary)
            .background {
                if hot {
                    shape.fill(accentGradient).opacity(0.9)
                } else {
                    shape.fill(GlassInk.idleScrim(for: colorScheme))
                }
            }
            .glassEffect(hot ? .regular.tint(palette.base.color) : .regular, in: shape)
            .glassEffectID(slice.id, in: glassSpace)
            .glassEffectTransition(.matchedGeometry)
    }

    private func solidPetal(_ slice: WheelSlice, _ index: Int, _ model: WheelModel) -> some View {
        let hot = model.highlighted == index
        let shape = PetalShape(slot: index, count: model.slices.count)
        return ZStack {
            if hot { shape.fill(accentGradient) } else { shape.fill(Color(white: 0.18)) }
            label(
                slice, index, model, colour: hot ? store.appearance.palette.labelOnAccent.color : .white.opacity(0.96))
        }
        .scaleEffect(hot ? 1.05 : 1)
    }

    /// Highlight fill from the one accent token: light → base → dark from the petal's inner to outer radius.
    private var accentGradient: RadialGradient {
        let palette = store.appearance.palette
        return RadialGradient(
            stops: [
                .init(color: palette.light.color, location: 0.2), .init(color: palette.base.color, location: 0.56),
                .init(color: palette.dark.color, location: 1),
            ], center: .center, startRadius: WheelLayout.geometry.petalInner,
            endRadius: WheelLayout.geometry.petalOuter)
    }

    private func label(_ slice: WheelSlice, _ index: Int, _ model: WheelModel, colour: Color) -> some View {
        PetalLabel(
            slice: slice, position: WheelLayout.labelPoint(slot: index, count: model.slices.count), colour: colour
        )
        .frame(width: WheelLayout.geometry.panelSide, height: WheelLayout.geometry.panelSide)
        .opacity(store.isExpanded ? 1 : 0)
    }

    private var hubColour: Color { store.theme == .solid ? .white : .primary }

    private var introAnimation: Animation {
        store.appearance.reduceMotion
            ? .easeOut(duration: WheelTiming.reducedMotionFade)
            : .timingCurve(0.18, 0.82, 0.24, 1.0, duration: WheelTiming.intro)
    }

    /// Reduce Motion turns springs into short fades (03a §2.7).
    /// The glassEffectID morph, or the Reduce Motion fade (`WheelMotion`).
    private var modeSwitch: Animation {
        let step = WheelMotion.modeSwitch(reduceMotion: store.appearance.reduceMotion)
        return step.isFade
            ? .easeOut(duration: step.duration) : .spring(duration: step.duration, bounce: WheelTiming.morphBounce)
    }

    private func motion(_ animation: Animation) -> Animation {
        store.appearance.reduceMotion ? .easeOut(duration: WheelTiming.reducedMotionFade) : animation
    }
}
