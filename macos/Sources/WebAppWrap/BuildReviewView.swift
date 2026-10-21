import AppKit
import SwiftUI
import WebAppWrapKit

/// The Build Apps page in My Apps: what's about to be built and why, then each app's progress
/// and result. Nothing is built until you click Build.
struct BuildReviewView: View {
    @ObservedObject var model: BuilderModel
    let plan: BuilderModel.BuildPlan

    private var isBuilding: Bool { model.status.isBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List {
                ForEach(plan.targets) { record in
                    BuildPlanRow(model: model, plan: plan, record: record, outcome: plan.outcomes[record.id], isBuilding: isBuilding)
                }
            }
            .frame(height: 300)

            VStack(alignment: .leading, spacing: 4) {
                if plan.skipped > 0 {
                    Label("\(plan.skipped) app\(plan.skipped == 1 ? " is" : "s are") up to date and will be skipped.", systemImage: "checkmark.circle")
                }
                if replacedCount > 0 {
                    Label("\(replacedCount) existing app\(replacedCount == 1 ? " is" : "s are") moved to the Trash first. Sign-ins and settings are kept.", systemImage: "trash")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 10) {
                HelpButton()
                StatusView(model: model)
                Spacer()
                if plan.isFinished {
                    Button("Done") { model.closeBuild() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Back") { model.closeBuild() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isBuilding)
                    Button("Build") { model.startBuild() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isBuilding)
                }
            }
            .frame(minHeight: 28)
        }
        .padding(24)
    }

    private var count: String {
        "\(plan.targets.count) App\(plan.targets.count == 1 ? "" : "s")"
    }

    private var title: String {
        if plan.isFinished { return "Built \(count)" }
        return isBuilding ? "Building \(count)…" : "Build \(count)"
    }

    private var subtitle: String {
        if plan.isFinished { return "Here’s how each app went." }
        if isBuilding { return "You can keep using other apps while this runs." }
        return "Here’s what will happen. Nothing is built until you click Build."
    }

    private var replacedCount: Int { plan.replacing.count }
}

/// One app on the Build Apps page: where it goes, why it's built, and how it went.
private struct BuildPlanRow: View {
    @ObservedObject var model: BuilderModel
    let plan: BuilderModel.BuildPlan
    let record: AppRecord
    let outcome: BuilderModel.BuildPlan.Outcome?
    let isBuilding: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.settings.name).lineLimit(1).truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            state
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        let path = model.appURL(for: record).path
        let reason = plan.reasons[record.id].map(\.description) ?? "Rebuild"
        let action = plan.replacing.contains(record.id) ? "Replaces" : "Creates"
        return "\(reason) · \(action) \(path)"
    }

    @ViewBuilder private var state: some View {
        switch outcome {
        case let .built(app):
            Label("Built", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Button("Open") { model.open(app) }
                .controlSize(.small)
        case let .failed(message):
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .help(message)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 200, alignment: .trailing)
                .textSelection(.enabled)
        case nil:
            if case let .buildingList(_, _, name) = model.status, name == record.settings.location.name {
                ProgressView().controlSize(.small)
            } else if isBuilding {
                Text("Waiting").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
