import PhotosUI
import SwiftUI
import UIKit

private enum ProfileEditFocusField: Hashable {
  case displayName
  case username
  case bio
}

struct EditProfileView: View {
  private enum SavePhase: Equatable {
    case idle
    case preparing
    case uploadingAvatar
    case uploadingCover
    case saving

    var titleKey: LocalizedStringKey? {
      switch self {
      case .idle: nil
      case .preparing: "profile.edit.state.preparing"
      case .uploadingAvatar: "profile.edit.state.uploading_avatar"
      case .uploadingCover: "profile.edit.state.uploading_cover"
      case .saving: "profile.edit.state.saving"
      }
    }
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  let user: MaxUser

  @State private var displayName: String
  @State private var username: String
  @State private var bio: String
  @State private var avatarImage: UIImage?
  @State private var coverImage: UIImage?
  @State private var avatarPickerItem: PhotosPickerItem?
  @State private var coverPickerItem: PhotosPickerItem?
  @State private var cropRequest: ProfileCropRequest?
  @State private var expandedDemoKind: ProfileImageKind?
  @State private var savePhase: SavePhase = .idle
  @State private var presentedError: ProductError?
  @State private var showDiscardConfirm = false
  @FocusState private var focusedField: ProfileEditFocusField?

  private var isSaving: Bool { savePhase != .idle }

  private var hasChanges: Bool {
    displayName != user.displayName
      || username != (user.username ?? "")
      || bio != (user.bio ?? "")
      || avatarImage != nil
      || coverImage != nil
  }

  private static func sanitizedUsername(_ raw: String) -> String {
    String(raw.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(40))
  }

  private func attemptCancel() {
    if hasChanges { showDiscardConfirm = true } else { dismiss() }
  }

  private var canSave: Bool {
    !isSaving
      && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && username.count <= 40
      && bio.count <= 240
  }

  init(user: MaxUser) {
    self.user = user
    _displayName = State(initialValue: user.displayName)
    _username = State(initialValue: user.username ?? "")
    _bio = State(initialValue: user.bio ?? "")
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MaxSpace.lg) {
          ProfileEditPreview(
            displayName: displayName,
            username: username,
            bio: bio,
            avatarURL: user.avatarUrl,
            coverURL: user.coverUrl,
            avatarImage: avatarImage,
            coverImage: coverImage
          )

          ProfileAssetEditingSection(
            isDemoMode: model.isDemoMode,
            avatarPickerItem: $avatarPickerItem,
            coverPickerItem: $coverPickerItem,
            expandedDemoKind: $expandedDemoKind,
            chooseDemoArtwork: chooseDemoArtwork
          )

          ProfileIdentityFields(
            displayName: $displayName,
            username: $username,
            bio: $bio,
            focusedField: $focusedField
          )

          if let titleKey = savePhase.titleKey {
            HStack(spacing: MaxSpace.sm) {
              ProgressView()
              Text(titleKey)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MaxColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MaxSpace.md)
            .background(
              MaxColor.surface,
              in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
            )
            .accessibilityIdentifier("ui_profile_edit_progress")
          }

          if let presentedError {
            ProductErrorView(error: presentedError, retry: save)
          }

          // A full-width in-flow form CTA is a reading surface, not a compact
          // floating control, so it stays opaque instead of sampling the
          // animated mesh behind it. `accentForeground` keeps the label legible
          // on the bright accents (Solar Ink) as well as the deep ones.
          Button(action: save) {
            Label("profile.edit.save", systemImage: "checkmark")
              .foregroundStyle(palette.accentForeground)
          }
          .buttonStyle(.borderedProminent)
          .tint(palette.accent)
          .controlSize(.large)
          .frame(maxWidth: .infinity, minHeight: 52)
          .disabled(!canSave)
          .accessibilityIdentifier("ui_profile_edit_save")
        }
        .padding(.horizontal, MaxSpace.md)
        .padding(.vertical, MaxSpace.lg)
      }
      .scrollDismissesKeyboard(.interactively)
      .maxScreenBackground()
      .navigationTitle("profile.edit.title")
      .navigationBarTitleDisplayMode(.inline)
      .interactiveDismissDisabled(isSaving || hasChanges)
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel") { attemptCancel() }
            .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("profile.edit.save", action: save)
            .fontWeight(.semibold)
            .disabled(!canSave)
        }
      }
      .confirmationDialog("Discard changes?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
        Button("Discard", role: .destructive) { dismiss() }
        Button("Keep Editing", role: .cancel) {}
      }
      .onChange(of: username) { _, newValue in
        let cleaned = Self.sanitizedUsername(newValue)
        if cleaned != newValue { username = cleaned }
      }
      .onChange(of: avatarPickerItem) { _, item in
        loadPhoto(item, kind: .avatar)
      }
      .onChange(of: coverPickerItem) { _, item in
        loadPhoto(item, kind: .cover)
      }
      .fullScreenCover(item: $cropRequest) { request in
        ProfileImageCropEditor(request: request) { image in
          applyCroppedImage(image, kind: request.kind)
        }
      }
      .accessibilityIdentifier("ui_profile_edit_screen")
    }
  }

  private func chooseDemoArtwork(_ artwork: DemoProfileArtwork) {
    expandedDemoKind = nil
    cropRequest = ProfileCropRequest(kind: artwork.kind, image: artwork.makeImage())
  }

  private func loadPhoto(_ item: PhotosPickerItem?, kind: ProfileImageKind) {
    guard let item else { return }
    presentedError = nil
    savePhase = .preparing
    Task {
      defer {
        savePhase = .idle
        if kind == .avatar { avatarPickerItem = nil } else { coverPickerItem = nil }
      }
      do {
        guard let data = try await item.loadTransferable(type: Data.self),
              data.count <= 20 * 1_024 * 1_024,
              let image = UIImage(data: data) else {
          throw ProfileEditingError.invalidImage
        }
        cropRequest = ProfileCropRequest(kind: kind, image: image)
      } catch is CancellationError {
        return
      } catch {
        presentedError = ProductError(
          area: .profile,
          code: .uploadFailed,
          title: String(localized: "profile.edit.image_error.title"),
          reason: String(localized: "profile.edit.image_error.reason"),
          recoverySuggestion: String(localized: "profile.edit.image_error.recovery")
        )
      }
    }
  }

  private func applyCroppedImage(_ image: UIImage, kind: ProfileImageKind) {
    switch kind {
    case .avatar: avatarImage = image
    case .cover: coverImage = image
    }
  }

  private func save() {
    guard canSave else { return }
    focusedField = nil
    presentedError = nil
    Task { await saveChanges() }
  }

  private func saveChanges() async {
    var avatarURL = user.avatarUrl
    var coverURL = user.coverUrl
    do {
      if let avatarImage {
        savePhase = .uploadingAvatar
        avatarURL = try await upload(avatarImage, kind: .avatar)
      }
      if let coverImage {
        savePhase = .uploadingCover
        coverURL = try await upload(coverImage, kind: .cover)
      }

      savePhase = .saving
      let saved = await model.profileStore.update(
        ProfileUpdateRequest(
          displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
          username: username.trimmingCharacters(in: .whitespacesAndNewlines),
          bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
          avatarUrl: avatarURL,
          coverUrl: coverURL
        )
      )
      guard saved else { throw ProfileEditingError.updateFailed }
      savePhase = .idle
      dismiss()
    } catch is CancellationError {
      savePhase = .idle
    } catch {
      let code: ProductErrorCode = savePhase == .saving ? .profileUpdateFailed : .uploadFailed
      savePhase = .idle
      presentedError = ProductError(
        area: .profile,
        code: code,
        title: String(localized: code == .uploadFailed
          ? "profile.edit.upload_error.title"
          : "profile.edit.save_error.title"),
        reason: String(localized: code == .uploadFailed
          ? "profile.edit.upload_error.reason"
          : "profile.edit.save_error.reason"),
        recoverySuggestion: String(localized: "error.product.retry")
      )
    }
  }

  private func upload(_ image: UIImage, kind: ProfileImageKind) async throws -> URL {
    guard let data = image.jpegData(compressionQuality: 0.88) else {
      throw ProfileEditingError.invalidImage
    }
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("max-profile-\(kind.rawValue)-\(UUID().uuidString).jpg")
    try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    defer { try? FileManager.default.removeItem(at: fileURL) }
    guard let remoteURL = await model.profileStore.uploadImage(fileURL: fileURL, kind: kind) else {
      throw ProfileEditingError.uploadFailed
    }
    return remoteURL
  }
}

private enum ProfileEditingError: Error {
  case invalidImage
  case uploadFailed
  case updateFailed
}

private struct ProfileIdentityFields: View {
  private static let bioLimit = 240

  @Binding var displayName: String
  @Binding var username: String
  @Binding var bio: String
  var focusedField: FocusState<ProfileEditFocusField?>.Binding

  private var bioCounter: String {
    "\(bio.count.formatted()) / \(Self.bioLimit.formatted())"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      Text("profile.edit.identity")
        .font(.headline)
        .foregroundStyle(MaxColor.textPrimary)

      TextField("profile.edit.display_name", text: $displayName)
        .textContentType(.name)
        .focused(focusedField, equals: .displayName)
        .submitLabel(.next)
        .onSubmit { focusedField.wrappedValue = .username }
        .onChange(of: displayName) { _, value in
          if value.count > 80 { displayName = String(value.prefix(80)) }
        }
        .accessibilityIdentifier("ui_profile_edit_name")

      TextField("profile.edit.username", text: $username)
        .textContentType(.username)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused(focusedField, equals: .username)
        .submitLabel(.next)
        .onSubmit { focusedField.wrappedValue = .bio }
        .onChange(of: username) { _, value in
          if value.count > 40 { username = String(value.prefix(40)) }
        }
        .accessibilityIdentifier("ui_profile_edit_username")

      TextField("profile.edit.bio", text: $bio, axis: .vertical)
        .lineLimit(3...7)
        .focused(focusedField, equals: .bio)
        .submitLabel(.done)
        .onSubmit { focusedField.wrappedValue = nil }
        .onChange(of: bio) { _, value in
          if value.count > Self.bioLimit { bio = String(value.prefix(Self.bioLimit)) }
        }
        .accessibilityIdentifier("ui_profile_edit_bio")

      // Both numbers go through the same localised formatter so Arabic never
      // mixes Arabic-Indic and Western digits inside one run.
      Text(verbatim: bioCounter)
        .font(.caption.monospacedDigit())
        .foregroundStyle(MaxColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(Text("profile.edit.bio"))
        .accessibilityValue(Text(verbatim: bioCounter))
    }
    .textFieldStyle(.roundedBorder)
    .padding(MaxSpace.md)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
  }
}
