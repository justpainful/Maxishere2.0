import SwiftUI

/// Security-safe presentation for actionable product failures. The domain error
/// owns the sanitized details; this view never renders a raw response body.
struct ProductErrorView: View {
  let error: ProductError
  let retry: (() -> Void)?

  @State private var showsSupportDetails = false

  init(error: ProductError, retry: (() -> Void)? = nil) {
    self.error = error
    self.retry = retry
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      HStack(alignment: .top, spacing: MaxSpace.sm) {
        Image(systemName: symbolName)
          .font(.title3.weight(.semibold))
          .foregroundStyle(symbolColor)
          .frame(width: 32, height: 32)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: MaxSpace.xxs) {
          Text(verbatim: error.title)
            .font(.headline)
            .foregroundStyle(MaxColor.textPrimary)
          Text(verbatim: error.reason)
            .font(.subheadline)
            .foregroundStyle(MaxColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
          if let suggestion = error.recoverySuggestion {
            Text(verbatim: suggestion)
              .font(.caption)
              .foregroundStyle(MaxColor.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      if let retry {
        Button("common.retry", systemImage: "arrow.clockwise", action: retry)
          .buttonStyle(.glass)
          .accessibilityIdentifier("ui_error_retry")
      }

      DisclosureGroup("error.support_details", isExpanded: $showsSupportDetails) {
        Text(verbatim: error.supportDetails)
          .font(.caption.monospaced())
          .foregroundStyle(MaxColor.textSecondary)
          .textSelection(.enabled)
          .environment(\.layoutDirection, .leftToRight)
          .padding(.top, MaxSpace.xs)
          .accessibilityIdentifier("ui_error_support_details")
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(MaxColor.textSecondary)
      .accessibilityIdentifier("ui_error_details_toggle")
    }
    .padding(MaxSpace.md)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
        .stroke(MaxColor.line, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("ui_product_error")
  }

  private var symbolName: String {
    switch error.code {
    case .offline: "wifi.slash"
    case .sessionExpired: "person.crop.circle.badge.exclamationmark"
    case .accessDenied: "hand.raised.fill"
    case .notFound: "questionmark.folder"
    case .downloadFailed, .insufficientStorage: "arrow.down.circle"
    case .ratingSaveFailed: "star.slash"
    case .uploadFailed, .profileUpdateFailed: "arrow.up.circle"
    case .serverUnavailable, .invalidResponse, .unknown: "exclamationmark.triangle.fill"
    default: "exclamationmark.triangle.fill"
    }
  }

  private var symbolColor: some ShapeStyle {
    switch error.code {
    case .offline, .serverUnavailable, .invalidResponse, .unknown:
      MaxColor.warning
    case .sessionExpired, .accessDenied, .notFound, .downloadFailed,
         .insufficientStorage, .ratingSaveFailed, .uploadFailed, .profileUpdateFailed:
      MaxColor.danger
    default:
      MaxColor.danger
    }
  }
}
