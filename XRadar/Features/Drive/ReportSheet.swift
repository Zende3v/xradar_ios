import SwiftUI
import XRadarCore

/// Quick-pick report sheet, role-gated: only the categories the account may create, six per
/// page. Picking one asks which way it is, and files it in the driver's own direction by itself
/// after a few seconds, hands-free.
struct ReportSheet: View {
    let role: Role
    let onReport: (ReportDraft) -> Void

    @State private var selected: ReportType?
    @State private var page = 0

    private static let perPage = 6
    private static let perRow = 3
    /// Two-line labels fit, and every page keeps the height of a full one.
    private static let tileHeight: CGFloat = 120

    var body: some View {
        DriveSheet {
            if let selected {
                DirectionStep(type: selected, onBack: { self.selected = nil }, onReport: onReport)
            } else {
                picker
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        let available = ReportType.picker.filter { $0.allowed(for: role) }
        let pages = stride(from: 0, to: available.count, by: Self.perPage).map {
            Array(available[$0..<min($0 + Self.perPage, available.count)])
        }
        Text("Signaler")
            .font(.xrTitle)
            .foregroundStyle(XRadarColor.textPrimary)
        TabView(selection: $page) {
            ForEach(pages.indices, id: \.self) { index in
                grid(pages[index]).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: Self.tileHeight * 2 + XRadarSpacing.md)
        if pages.count > 1 {
            PageDots(count: pages.count, current: page)
        }
    }

    private func grid(_ types: [ReportType]) -> some View {
        VStack(spacing: XRadarSpacing.md) {
            ForEach(0..<(Self.perPage / Self.perRow), id: \.self) { row in
                HStack(spacing: XRadarSpacing.md) {
                    ForEach(0..<Self.perRow, id: \.self) { column in
                        let index = row * Self.perRow + column
                        if index < types.count {
                            ReportTile(type: types[index], height: Self.tileHeight) {
                                selected = types[index]
                            }
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.tileHeight)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The sheet the HUD's pickers open in (reports, speed limit), fitted to its content.
struct DriveSheet<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var height: CGFloat = 360

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XRadarSpacing.lg) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, XRadarSpacing.lg)
            .padding(.top, XRadarSpacing.xxl)
            .padding(.bottom, XRadarSpacing.lg)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
    }
}

/// A sheet step's title, with the way back to the previous step.
struct SheetBackTitle: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: XRadarSpacing.sm) {
            Button(action: onBack) {
                Image(XRadarSymbol.chevronLeft)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(XRadarColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retour")
            Text(title)
                .font(.xrTitle)
                .foregroundStyle(XRadarColor.textPrimary)
        }
    }
}

/// The hands-free countdown: full, then empty after [duration], when the step sends itself.
struct AutoSendBar: View {
    var duration: Double = 5

    @State private var remaining: CGFloat = 1

    var body: some View {
        Capsule()
            .fill(XRadarColor.surfaceHigh)
            .frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(XRadarColor.accent)
                        .frame(width: proxy.size.width * remaining)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: duration)) { remaining = 0 }
            }
    }
}

/// "Mon sens" or "Sens opposé". Nobody should have to answer while driving, so the driver's own
/// direction is sent by itself once the countdown runs out.
private struct DirectionStep: View {
    let type: ReportType
    let onBack: () -> Void
    let onReport: (ReportDraft) -> Void

    @State private var plate = ""
    @State private var auto = true
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: XRadarSpacing.lg) {
            SheetBackTitle(title: type.label) {
                auto = false
                onBack()
            }
            if type.needsPlate {
                TextField("Plaque (facultatif)", text: $plate)
                    .font(.xrBody)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(XRadarSpacing.md)
                    .background(XRadarColor.surface, in: .rect(cornerRadius: XRadarRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: XRadarRadius.md).strokeBorder(XRadarColor.border, lineWidth: 1)
                    }
                    .onChange(of: plate) { _, value in
                        // Typing means the driver is not in a hurry: stop the timer.
                        auto = false
                        let upper = value.uppercased()
                        if upper != value { plate = upper }
                    }
                Text("Facultative — elle reste privée et sert seulement à resserrer la zone probable.")
                    .font(.xrFootnote)
                    .foregroundStyle(XRadarColor.textTertiary)
            }
            Text("Dans quel sens ?")
                .font(.xrSubhead)
                .foregroundStyle(XRadarColor.textSecondary)
            HStack(spacing: XRadarSpacing.md) {
                XRadarButton(title: "Mon sens", fillWidth: true) { send(ReportDirection.same) }
                XRadarButton(title: "Sens opposé", variant: .secondary, fillWidth: true) { send(ReportDirection.opposite) }
            }
            if auto {
                AutoSendBar()
            }
        }
        .task(id: auto) {
            guard auto else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, auto else { return }
            send(ReportDirection.same)
        }
    }

    private func send(_ direction: String) {
        guard !sent else { return }
        sent = true
        let trimmed = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        onReport(ReportDraft(type: type, direction: direction, plate: trimmed.isEmpty ? nil : trimmed))
    }
}

private struct ReportTile: View {
    let type: ReportType
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: XRadarSpacing.sm) {
                // Every category on the same disc; the icon in white with a soft glow.
                ZStack {
                    Circle().fill(XRadarColor.glowTile)
                    if let icon = type.pickerIcon {
                        XRadarGlowIcon(icon: icon, tint: XRadarColor.glowIcon, size: 30)
                    }
                }
                .frame(width: 60, height: 60)
                Text(type.label)
                    .font(.xrCaption)
                    .foregroundStyle(XRadarColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Page dots: the only hint that there is more to the side.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                let size: CGFloat = index == current ? 7 : 6
                Circle()
                    .fill(index == current ? XRadarColor.accent : XRadarColor.borderStrong)
                    .frame(width: size, height: size)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

