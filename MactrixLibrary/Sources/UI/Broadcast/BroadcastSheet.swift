import Models
import SwiftUI
import Tokens

/// The step the broadcast sheet shows (MATRIX-168).
public enum BroadcastSheetStep: Equatable, Sendable {
    /// The text field and the target checklist.
    case compose
    /// The message, the count, and the explicit send button.
    case review
    /// The run: in progress, or finished.
    case progress
}

/// What the broadcast sheet asks its owner to do.
public struct BroadcastSheetActions {
    /// Opens the review step.
    public var review: () -> Void
    /// Goes back to the compose step.
    public var back: () -> Void
    /// Starts the sends. Only the review step calls it.
    public var send: () -> Void
    /// Stops the run after the send in flight.
    public var stop: () -> Void
    /// Sends again to the failed targets.
    public var retryFailed: () -> Void
    /// Closes the sheet: Cancel, Done, or Escape.
    public var close: () -> Void

    public init(
        review: @escaping () -> Void = {},
        back: @escaping () -> Void = {},
        send: @escaping () -> Void = {},
        stop: @escaping () -> Void = {},
        retryFailed: @escaping () -> Void = {},
        close: @escaping () -> Void = {}
    ) {
        self.review = review
        self.back = back
        self.send = send
        self.stop = stop
        self.retryFailed = retryFailed
        self.close = close
    }
}

/// The broadcast sheet (MATRIX-168; contract §11, 2026-11-16): one text
/// message to each chat the rail filter shows.
///
/// Three steps in one sheet. Compose: the text and the target checklist.
/// Review: the message, "This sends one message to N chats. It cannot be
/// recalled.", and the send button; above
/// `BroadcastConfirmation.typedCountThreshold` targets the user types the
/// count. Progress: each target as waiting, sending, sent, or failed, with
/// Stop while the run is active, and the summary, Retry Failed, and Done
/// when it ended.
///
/// The view makes no SDK call and holds no state: the owner holds the draft
/// and the `BroadcastRun`.
///
/// Usage:
/// ```swift
/// BroadcastSheet(filterName: "Work", targets: targets, draft: $draft, typedCount: $typedCount,
///                step: step, states: run?.states ?? [:], phase: run?.phase ?? .idle,
///                imageLoader: client, actions: actions)
/// ```
public struct BroadcastSheet: View {
    let filterName: String
    let targets: [BroadcastTarget]
    @Binding var draft: BroadcastDraft
    @Binding var typedCount: String
    let step: BroadcastSheetStep
    let states: [String: BroadcastTargetState]
    let phase: BroadcastRun.Phase
    let imageLoader: ImageLoader?
    let actions: BroadcastSheetActions

    /// Set by snapshot tests to swap the indeterminate spinner for a static
    /// substitute. Production never sets it.
    @Environment(\.usesStaticProgressIndicators) private var usesStaticProgressIndicators

    private static let width: CGFloat = 460
    private static let listMaxHeight: CGFloat = 264
    private static let statusSize: CGFloat = 16

    /// - Parameters:
    ///   - filterName: The label's or the space's name.
    ///   - targets: Every target of the filter, in sidebar order.
    ///   - draft: The text and the checked targets.
    ///   - typedCount: The content of the review step's count field.
    ///   - step: The step to show.
    ///   - states: The run's target states, by target ID. Empty before a run.
    ///   - phase: The run's phase. `.idle` before a run.
    ///   - imageLoader: Loads the avatars.
    ///   - actions: What the buttons do.
    public init(
        filterName: String,
        targets: [BroadcastTarget],
        draft: Binding<BroadcastDraft>,
        typedCount: Binding<String>,
        step: BroadcastSheetStep,
        states: [String: BroadcastTargetState] = [:],
        phase: BroadcastRun.Phase = .idle,
        imageLoader: ImageLoader?,
        actions: BroadcastSheetActions
    ) {
        self.filterName = filterName
        self.targets = targets
        self._draft = draft
        self._typedCount = typedCount
        self.step = step
        self.states = states
        self.phase = phase
        self.imageLoader = imageLoader
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Broadcast to \(filterName)", systemImage: "megaphone")
                .font(.title2)
                .bold()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            switch step {
            case .compose: compose
            case .review: review
            case .progress: progress
            }
        }
        .padding(20)
        .sheetContentWidth(Self.width)
        .cancelsOnExitCommand(step == .review ? actions.back : actions.close)
        .interactiveDismissDisabled(isActive)
    }

    // MARK: - Values

    private var selectedTargets: [BroadcastTarget] {
        draft.selectedTargets(in: targets)
    }

    private var isActive: Bool {
        phase == .running || phase == .stopping
    }

    private var summary: BroadcastSummary {
        var summary = BroadcastSummary()
        for target in selectedTargets {
            switch states[target.id] ?? .waiting {
            case .sent: summary.sent += 1
            case .failed: summary.failed += 1
            case .waiting, .sending: summary.notSent += 1
            }
        }
        return summary
    }

    // MARK: - Compose

    @ViewBuilder private var compose: some View {
        TextField("Message", text: $draft.text, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(3 ... 8)

        HStack {
            Text("\(selectedTargets.count) of \(targets.count) chats selected")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button("Select All") { draft.selectAll(targets) }
                .disabled(selectedTargets.count == targets.count)
            Button("Select None") { draft.selectNone() }
                .disabled(selectedTargets.isEmpty)
        }
        .controlSize(.small)

        targetList(targets, rows: .check)

        HStack {
            Spacer()
            Button("Cancel", action: actions.close)
            Button("Review…", action: actions.review)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canReview(targets: targets))
        }
    }

    private func checkRow(_ target: BroadcastTarget) -> some View {
        let isSelected = draft.selectedIds.contains(target.id)
        return Button {
            draft.setSelected(!isSelected, id: target.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: Self.statusSize))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                identity(of: target)
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Review

    @ViewBuilder private var review: some View {
        let count = selectedTargets.count
        let needsTypedCount = BroadcastConfirmation.needsTypedCount(targetCount: count)

        messagePreview

        Text(count == 1
            ? "This sends one message to 1 chat. It cannot be recalled."
            : "This sends one message to \(count) chats. It cannot be recalled.")
            .fixedSize(horizontal: false, vertical: true)

        targetList(selectedTargets, rows: .plain)

        if needsTypedCount {
            HStack(spacing: 8) {
                Text("To confirm, type the number of chats (\(String(count))):")
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Count", text: $typedCount)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .accessibilityLabel("Number of chats")
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
            }
        }

        HStack {
            Button("Back", action: actions.back)
            Spacer()
            // Not the default button: Return never sends.
            Button(count == 1 ? "Send to 1 Chat" : "Send to \(count) Chats", action: actions.send)
                .disabled(!BroadcastConfirmation.isConfirmed(targetCount: count, typedCount: typedCount))
        }
    }

    /// The message as it goes out, quoted.
    private var messagePreview: some View {
        Text(draft.outgoingText)
            .lineLimit(8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Progress

private extension BroadcastSheet {
    @ViewBuilder var progress: some View {
        let summary = summary

        messagePreview

        VStack(alignment: .leading, spacing: 4) {
            Text(progressLine(summary))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if phase == .finished {
                Text("A message that fails later shows Retry in its chat. Sent messages cannot be recalled here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        targetList(selectedTargets, rows: .status)

        HStack {
            if phase == .finished, summary.failed > 0 {
                Button("Retry Failed", action: actions.retryFailed)
            }
            Spacer()
            if isActive {
                Button("Stop", action: actions.stop)
                    .disabled(phase == .stopping)
            } else {
                Button("Done", action: actions.close)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    func progressLine(_ summary: BroadcastSummary) -> String {
        switch phase {
        case .idle, .running:
            return "Sending: \(summary.completed) of \(summary.total)"
        case .stopping:
            return "Stopping after the current chat: \(summary.completed) of \(summary.total)"
        case .finished:
            var parts = ["\(summary.sent) sent"]
            if summary.failed > 0 {
                parts.append("\(summary.failed) failed")
            }
            if summary.notSent > 0 {
                parts.append("\(summary.notSent) not sent")
            }
            return parts.joined(separator: " · ")
        }
    }

    func failureReason(of target: BroadcastTarget) -> String? {
        if case let .failed(reason) = states[target.id] {
            return reason
        }
        return nil
    }

    @ViewBuilder
    func status(of target: BroadcastTarget) -> some View {
        switch states[target.id] ?? .waiting {
        case .waiting:
            Text(phase == .finished ? "Not sent" : "Waiting")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .sending:
            spinner
                .accessibilityLabel("Sending")
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Self.statusSize))
                .foregroundStyle(.green)
                .accessibilityLabel("Sent")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Self.statusSize))
                .foregroundStyle(.orange)
                .accessibilityLabel("Failed")
        }
    }

    @ViewBuilder var spinner: some View {
        if usesStaticProgressIndicators {
            // Snapshot-only: a ring drawn with SwiftUI shapes, at the small
            // spinner's 16 pt (see `RecoveryKeyEntrySheet`).
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: Self.statusSize, height: Self.statusSize)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: - Target list

    /// What a row of the target list shows next to the chat.
    enum RowKind {
        /// A checkbox: the compose step.
        case check
        /// Nothing: the review step.
        case plain
        /// The send state: the progress step.
        case status
    }

    @ViewBuilder
    func row(_ target: BroadcastTarget, kind: RowKind) -> some View {
        switch kind {
        case .check:
            checkRow(target)
        case .plain:
            HStack(spacing: 8) {
                identity(of: target)
                Spacer(minLength: 8)
            }
        case .status:
            HStack(alignment: .center, spacing: 8) {
                identity(of: target, reason: failureReason(of: target))
                Spacer(minLength: 8)
                status(of: target)
            }
        }
    }

    /// The avatar and the title of a target, with the failure reason under
    /// the title.
    func identity(of target: BroadcastTarget, reason: String? = nil) -> some View {
        // The network badge scales with the avatar, but on this 24 pt avatar
        // it would cover most of the face (as in the label sheet).
        var avatarModel = target.row
        avatarModel.network = nil
        avatarModel.account = nil
        avatarModel.additionalNetworks = []
        avatarModel.memberBadges = []
        return HStack(spacing: 8) {
            ChatListAvatar(model: avatarModel, size: LabelToken.sheetAvatarSize, imageLoader: imageLoader)
            VStack(alignment: .leading, spacing: 1) {
                Text(target.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The scrollable list of targets. Opaque content: no glass here
    /// (hard rule 2).
    func targetList(_ shown: [BroadcastTarget], rows: RowKind) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { target in
                    row(target, kind: rows)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: Self.listMaxHeight)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}
