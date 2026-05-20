import Foundation
import SwiftGetXCore

struct PendingNativeHandoffResolution: Equatable {
    var handoff: NativeHandoffAck
    var decision: NativeHandoffAckDecision
}

enum PendingNativeHandoffPolicy {
    static func expirationResolution(
        draft: DownloadDraft?,
        now: Date = .now
    ) -> PendingNativeHandoffResolution? {
        guard let draft,
              let handoffAck = draft.handoffAck,
              handoffAck.isExpired(now: now)
        else {
            return nil
        }

        return PendingNativeHandoffResolution(
            handoff: handoffAck,
            decision: .rejected(
                reason: "expired",
                requiresUserConfirmation: draft.isBrowserTakeover,
                message: "SwiftGetX download confirmation expired before it was accepted"
            )
        )
    }

    static func replacementResolution(
        current: DownloadDraft?,
        incoming: DownloadDraft?
    ) -> PendingNativeHandoffResolution? {
        guard let current,
              let handoffAck = current.handoffAck,
              current.handoffAck != incoming?.handoffAck
        else {
            return nil
        }

        return PendingNativeHandoffResolution(
            handoff: handoffAck,
            decision: .rejected(
                reason: "supersededByNewRequest",
                requiresUserConfirmation: current.isBrowserTakeover,
                message: "SwiftGetX download confirmation was replaced by another request"
            )
        )
    }

    static func rejectIfReplaced(current: DownloadDraft?, incoming: DownloadDraft?) {
        guard let resolution = replacementResolution(current: current, incoming: incoming) else {
            return
        }

        acknowledge(resolution)
    }

    static func acknowledge(_ resolution: PendingNativeHandoffResolution) {
        Task.detached {
            try? await NativeHandoffAckClient.acknowledge(
                resolution.decision,
                handoff: resolution.handoff
            )
        }
    }
}
