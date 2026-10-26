import SwiftUI
import AppKit

/// Direct manipulation: a dedicated grip lifts the row immediately; neighboring
/// rows move into their provisional slots while the pointer remains in control.
struct ReorderableServiceList: View {
    let store: MonitorStore
    let openDetails: (Provider) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggedID: String?
    @State private var origin = 0
    @State private var destination = 0
    @State private var translation: CGFloat = 0
    @State private var settling = false
    @State private var dragGeneration = 0
    @GestureState private var pointerDragging = false
    private let pitch: CGFloat = 60
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84) }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(store.providers.enumerated()), id: \.element.id) { index, provider in
                let lifted = draggedID == provider.id
                let slot = ReorderSlots.slot(for: index, origin: origin, destination: destination, dragging: draggedID != nil)
                ServicePriorityRow(provider: provider, store: store, lifted: lifted, openDetails: { if draggedID == nil { openDetails(provider) } }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(lifted ? .primary : .secondary)
                        .frame(width: 28, height: 44).contentShape(Rectangle())
                        .help("Drag \(provider.name) to reorder")
                        .accessibilityLabel("Reorder \(provider.name)")
                        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("service-priority"))
                            .updating($pointerDragging) { _, active, _ in active = true }
                            .onChanged { value in
                                guard !settling, draggedID == nil || draggedID == provider.id else { return }
                                if draggedID == nil { dragGeneration += 1; draggedID = provider.id; origin = index; destination = index }
                                translation = value.translation.height
                                let target = ReorderSlots.destination(origin: origin, translation: translation, pitch: pitch, count: store.providers.count)
                                if destination != target { destination = target; NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                            }
                            .onEnded { _ in finishDrag() })
                }
                .frame(height: 54)
                .scaleEffect(lifted && !reduceMotion ? 1.015 : 1)
                .animation(spring, value: lifted)
                .offset(y: lifted ? translation : CGFloat(slot - index) * pitch)
                .animation(spring, value: slot)
                .zIndex(lifted ? 1 : 0)
                .contextMenu {
                    Button("Show in menu bar") { store.reorderProviders(moving: [provider.id], before: store.primaryProvider?.id) }
                        .disabled(provider.id == store.primaryProvider?.id)
                    Button("Move up") { store.moveProviders(from: [index], to: index - 1) }.disabled(index == 0)
                    Button("Move down") { store.moveProviders(from: [index], to: index + 2) }.disabled(index == store.providers.count - 1)
                }
                .accessibilityAction(named: "Move up") { if index > 0 { store.moveProviders(from: [index], to: index - 1) } }
                .accessibilityAction(named: "Move down") { if index + 1 < store.providers.count { store.moveProviders(from: [index], to: index + 2) } }
            }
            if store.providers.isEmpty { Text("Choose services in Settings.").foregroundStyle(.secondary).padding(24) }
        }
        .frame(height: max(54, CGFloat(store.providers.count) * pitch - 6), alignment: .top)
        .coordinateSpace(name: "service-priority")
        .padding(.horizontal, 12).padding(.vertical, 10)
        .onChange(of: pointerDragging) { _, active in if !active && !settling { cancelDrag() } }
        .onChange(of: store.providers.map(\.id)) { _, _ in if !settling { cancelDrag() } }
        .onDisappear { cancelDrag() }
    }
    private func finishDrag() {
        guard let draggedID, !settling else { return }
        let target = destination
        settling = true
        let ids = store.providers.map(\.id).filter { $0 != draggedID }
        let before = target < ids.count ? ids[target] : nil
        // Commit on mouse-up, not in an animation callback that can be cancelled.
        store.reorderProviders(moving: [draggedID], before: before)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.draggedID = nil; translation = 0; settling = false
        }
    }

    private func cancelDrag() {
        guard draggedID != nil else { return }
        dragGeneration += 1
        withAnimation(spring) { draggedID = nil; translation = 0; settling = false }
    }
}
private struct ServicePriorityRow<Grip: View>: View {
    let provider: Provider
    let store: MonitorStore
    let lifted: Bool
    let openDetails: () -> Void
    @ViewBuilder let grip: () -> Grip
    private var reading: ServiceReading { store.reading(provider) }
    private var unavailable: Bool { reading.unavailable(at: store.now, maxAge: store.maxAge) }
    var body: some View {
        HStack(spacing: 6) {
            grip()
            Button(action: openDetails) {
                HStack(spacing: 10) {
                    ServiceLogo(provider: provider, size: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(provider.name).font(.body.weight(.medium))
                            Spacer()
                            Circle().fill(unavailable ? Color.secondary : reading.snapshot?.health.color ?? .secondary).frame(width: 6, height: 6)
                            Text(unavailable ? "Unavailable" : reading.snapshot?.health.title ?? "Checking").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(unavailable ? "Status unavailable" : reading.snapshot?.incidents.first?.name ?? reading.snapshot?.description ?? "Checking official status…")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 54).accessibilityLabel("Show \(provider.name) details")
        }.padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
        .background(Color.primary.opacity(lifted ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 10))
        .background {
            if lifted { RoundedRectangle(cornerRadius: 12).fill(.regularMaterial) }
        }
        .shadow(color: .black.opacity(lifted ? 0.22 : 0), radius: lifted ? 10 : 0, y: lifted ? 4 : 0)
    }
}
