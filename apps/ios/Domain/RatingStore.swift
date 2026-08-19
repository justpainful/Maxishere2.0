import Foundation
import Observation

@MainActor
@Observable
final class RatingStore {
  private let api: any MaxService

  private(set) var subjectsByFileID: [String: [RatingSubject]] = [:]
  private(set) var ratedEntries: [RatedMediaEntry] = []
  private(set) var isLoadingLibrary = false
  private(set) var loadingFileIDs = Set<String>()
  private(set) var updatingSubjectIDs = Set<String>()
  var presentedError: ProductError?

  init(api: any MaxService) {
    self.api = api
  }

  func reset() {
    subjectsByFileID = [:]
    ratedEntries = []
    isLoadingLibrary = false
    loadingFileIDs = []
    updatingSubjectIDs = []
    presentedError = nil
  }

  func subjects(for fileID: String) -> [RatingSubject] {
    subjectsByFileID[fileID] ?? []
  }

  func load(fileID: String) async {
    guard !loadingFileIDs.contains(fileID) else { return }
    loadingFileIDs.insert(fileID)
    defer { loadingFileIDs.remove(fileID) }
    do {
      let response = try await api.ratings(fileID: fileID)
      subjectsByFileID[fileID] = response.subjects
      presentedError = nil
    } catch is CancellationError {
      return
    } catch {
      presentedError = ProductError.from(error, area: .ratings, fallback: .ratingSaveFailed)
    }
  }

  func loadLibrary() async {
    guard !isLoadingLibrary else { return }
    isLoadingLibrary = true
    defer { isLoadingLibrary = false }
    do {
      let response = try await api.ratedMedia()
      ratedEntries = response.items
      for entry in response.items {
        subjectsByFileID[entry.media.id] = entry.subjects
      }
      presentedError = nil
    } catch is CancellationError {
      return
    } catch {
      presentedError = ProductError.from(error, area: .ratings)
    }
  }

  /// Commits one discrete value. Passing the selected value again clears it with score zero.
  /// Views may preview drag values locally; only gesture completion should call this method.
  func commit(fileID: String, subjectID: String, selectedScore: Int) async {
    guard (1...10).contains(selectedScore),
          let current = subjectsByFileID[fileID],
          let index = current.firstIndex(where: { $0.user.id == subjectID }),
          current[index].canEdit,
          !updatingSubjectIDs.contains(subjectID) else {
      return
    }

    let previous = current[index]
    let finalScore = previous.score == selectedScore ? 0 : selectedScore
    updateLocal(fileID: fileID, subjectID: subjectID, score: finalScore == 0 ? nil : finalScore)
    updatingSubjectIDs.insert(subjectID)
    defer { updatingSubjectIDs.remove(subjectID) }

    do {
      let response = try await api.setRating(
        fileID: fileID,
        targetUserID: subjectID,
        score: finalScore
      )
      updateLocal(fileID: fileID, subjectID: subjectID, score: response.score)
      presentedError = nil
    } catch {
      updateLocal(fileID: fileID, subjectID: subjectID, score: previous.score)
      presentedError = ProductError.from(error, area: .ratings, fallback: .ratingSaveFailed)
    }
  }

  private func updateLocal(fileID: String, subjectID: String, score: Int?) {
    guard var subjects = subjectsByFileID[fileID],
          let index = subjects.firstIndex(where: { $0.user.id == subjectID }) else {
      return
    }
    let previous = subjects[index]
    subjects[index] = RatingSubject(
      user: previous.user,
      score: score,
      updatedAt: previous.updatedAt,
      canEdit: previous.canEdit
    )
    subjectsByFileID[fileID] = subjects
    if let entryIndex = ratedEntries.firstIndex(where: { $0.media.id == fileID }) {
      let entry = ratedEntries[entryIndex]
      ratedEntries[entryIndex] = RatedMediaEntry(media: entry.media, subjects: subjects)
    }
  }
}
