import SwiftUI
import UIKit

/// Share links — a public, expiring window onto one item for someone with no
/// account. The sheet mints links (expiry + optional view budget) and manages
/// the ones that already exist: copy, watch the view counter, revoke. Mirrors
/// the desktop's ShareLinkSheet.
struct ShareLinkSheetView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let item: MaxMediaItem

  @State private var links: [MaxShareLink]?
  @State private var expiry: ExpiryChoice = .week
  @State private var budget: ViewBudget = .unlimited
  @State private var isCreating = false
  @State private var copiedID: String?
  @State private var errorMessage: String?

  private enum ExpiryChoice: String, CaseIterable, Identifiable {
    case hour, day, week, month

    var id: String { rawValue }

    var title: String {
      switch self {
      case .hour: "1 hour"
      case .day: "1 day"
      case .week: "7 days"
      case .month: "30 days"
      }
    }

    var seconds: Int {
      switch self {
      case .hour: 3_600
      case .day: 86_400
      case .week: 7 * 86_400
      case .month: 30 * 86_400
      }
    }
  }

  private enum ViewBudget: String, CaseIterable, Identifiable {
    case unlimited, one, five, twenty

    var id: String { rawValue }

    var title: String {
      switch self {
      case .unlimited: "Unlimited"
      case .one: "1"
      case .five: "5"
      case .twenty: "20"
      }
    }

    var views: Int? {
      switch self {
      case .unlimited: nil
      case .one: 1
      case .five: 5
      case .twenty: 20
      }
    }
  }

  /// Links still worth showing: not revoked, not past their expiry.
  private var activeLinks: [MaxShareLink] {
    (links ?? []).filter { link in
      guard link.revokedAt == nil else { return false }
      guard let expires = ChatKitTime.date(link.expiresAt) else { return true }
      return expires > Date()
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Expires after", selection: $expiry) {
            ForEach(ExpiryChoice.allCases) { choice in
              Text(verbatim: choice.title).tag(choice)
            }
          }
          Picker("View limit", selection: $budget) {
            ForEach(ViewBudget.allCases) { choice in
              Text(verbatim: choice.title).tag(choice)
            }
          }
          Button {
            create()
          } label: {
            if isCreating {
              ProgressView()
                .frame(maxWidth: .infinity)
            } else {
              Label("Create Link", systemImage: "link")
                .frame(maxWidth: .infinity)
            }
          }
          .disabled(isCreating)
          .accessibilityIdentifier("ui_share_link_create")
        } footer: {
          Text("Anyone with the link can view this item until it expires or runs out of views.")
        }

        if !activeLinks.isEmpty {
          Section("Active links") {
            ForEach(activeLinks) { link in
              linkRow(link)
            }
          }
        }

        if let errorMessage {
          Section {
            Text(verbatim: errorMessage)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("Share Link")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
      }
      .task { await load() }
    }
    .presentationDetents([.medium, .large])
    .accessibilityIdentifier("ui_share_link_sheet")
  }

  private func linkRow(_ link: MaxShareLink) -> some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: "link")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: link.url ?? link.token)
          .font(.caption)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(verbatim: linkMeta(link))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      if let urlString = link.url, let url = URL(string: urlString) {
        ShareLink(item: url) {
          Image(systemName: "square.and.arrow.up")
            .font(.caption)
        }
        .buttonStyle(.borderless)
      }

      Button {
        copy(link)
      } label: {
        Image(systemName: copiedID == link.id ? "checkmark" : "doc.on.doc")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(Text("Copy link"))

      Button(role: .destructive) {
        revoke(link)
      } label: {
        Image(systemName: "xmark.circle")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(Text("Revoke link"))
    }
  }

  /// "Expires in 6 days · 3 views" — the row's second line.
  private func linkMeta(_ link: MaxShareLink) -> String {
    var parts: [String] = []
    if let expires = ChatKitTime.date(link.expiresAt) {
      let formatter = RelativeDateTimeFormatter()
      formatter.unitsStyle = .full
      parts.append("Expires \(formatter.localizedString(for: expires, relativeTo: Date()))")
    }
    if let maxViews = link.maxViews {
      parts.append("\(link.viewCount)/\(maxViews) views")
    } else {
      parts.append("\(link.viewCount) views")
    }
    return parts.joined(separator: " · ")
  }

  private func load() async {
    do {
      links = try await model.apiClient.shareLinks(mediaID: item.id)
    } catch {
      links = []
    }
  }

  private func create() {
    guard !isCreating else { return }
    isCreating = true
    errorMessage = nil
    Task {
      defer { isCreating = false }
      do {
        let link = try await model.apiClient.createShareLink(
          mediaID: item.id,
          expiresInSeconds: expiry.seconds,
          maxViews: budget.views
        )
        links = [link] + (links ?? [])
        copy(link)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func copy(_ link: MaxShareLink) {
    guard let url = link.url else { return }
    UIPasteboard.general.string = url
    copiedID = link.id
  }

  /// Optimistic: the row disappears immediately; a failed revoke reloads truth.
  private func revoke(_ link: MaxShareLink) {
    links = (links ?? []).filter { $0.id != link.id }
    Task {
      do {
        _ = try await model.apiClient.revokeShareLink(id: link.id)
      } catch {
        await load()
      }
    }
  }
}
