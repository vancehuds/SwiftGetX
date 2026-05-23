import Foundation
import SwiftGetXCore

enum BrowserDownloadRecoveryBlockReason: Equatable {
    case runtimeCredentialsUnavailable([String])
    case unsupportedRequestReplay(method: String, hasBody: Bool)

    var rejectedReason: String {
        switch self {
        case .runtimeCredentialsUnavailable:
            "runtimeCredentialsUnavailable"
        case .unsupportedRequestReplay:
            "unsupportedRequestReplay"
        }
    }

    var title: String {
        switch self {
        case .runtimeCredentialsUnavailable:
            L10n.string("browser_recovery_session_required_title")
        case .unsupportedRequestReplay:
            L10n.string("browser_recovery_request_replay_title")
        }
    }

    var message: String {
        switch self {
        case .runtimeCredentialsUnavailable(let credentialNames):
            L10n.string(
                "browser_recovery_session_required_message",
                credentialSummary(credentialNames)
            )
        case .unsupportedRequestReplay(let method, let hasBody):
            L10n.string(
                "browser_recovery_request_replay_message",
                method,
                hasBody ? L10n.string("browser_recovery_request_body_suffix") : ""
            )
        }
    }

    var shortStatus: String {
        switch self {
        case .runtimeCredentialsUnavailable:
            L10n.string("browser_recovery_session_required_short")
        case .unsupportedRequestReplay:
            L10n.string("browser_recovery_request_replay_short")
        }
    }

    private func credentialSummary(_ credentialNames: [String]) -> String {
        let names = credentialNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return names.isEmpty ? L10n.string("browser_recovery_credentials_generic") : names.joined(separator: ", ")
    }
}

enum BrowserDownloadRecoveryPolicy {
    static func blockReason(
        for task: DownloadTask,
        runtimeBrowserContext: BrowserDownloadContext?
    ) -> BrowserDownloadRecoveryBlockReason? {
        guard task.kind == .http, let context = task.browserContext else { return nil }
        if context.hasUnsupportedRequestReplay {
            return unsupportedRequestReplayReason(for: context)
        }
        if context.hasRuntimeOnlyCredentials, runtimeBrowserContext == nil {
            return .runtimeCredentialsUnavailable(context.runtimeCredentialNames ?? [])
        }
        return nil
    }

    static func persistedRequirement(for task: DownloadTask) -> BrowserDownloadRecoveryBlockReason? {
        guard task.kind == .http, let context = task.browserContext else { return nil }
        if context.hasUnsupportedRequestReplay {
            return unsupportedRequestReplayReason(for: context)
        }
        if context.hasRuntimeOnlyCredentials {
            return .runtimeCredentialsUnavailable(context.runtimeCredentialNames ?? [])
        }
        return nil
    }

    static func nativeHandoffRejection(for draft: DownloadDraft) -> NativeHandoffAckDecision? {
        guard draft.isTrustedNativeHandoff,
              let context = draft.browserContext,
              context.hasUnsupportedRequestReplay
        else {
            return nil
        }
        let reason = unsupportedRequestReplayReason(for: context)
        return .rejected(
            reason: reason.rejectedReason,
            requiresUserConfirmation: draft.requiresUserConfirmation || draft.isBrowserTakeover,
            message: reason.message
        )
    }

    private static func unsupportedRequestReplayReason(
        for context: BrowserDownloadContext
    ) -> BrowserDownloadRecoveryBlockReason {
        .unsupportedRequestReplay(
            method: context.normalizedMethod,
            hasBody: context.bodyMetadata != nil
        )
    }
}
