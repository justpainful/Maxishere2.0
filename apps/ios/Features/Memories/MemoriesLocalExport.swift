import Foundation
import Photos
import PhotosUI
import UIKit

@MainActor
enum MemoriesLocalExportPresenter {
  static func presentShare(for url: URL) {
    let controller = UIActivityViewController(
      activityItems: [url],
      applicationActivities: nil
    )
    controller.completionWithItemsHandler = { _, _, _, _ in
      try? FileManager.default.removeItem(at: url)
    }
    present(controller)
  }

  static func presentDocumentExport(for url: URL) {
    let controller = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    present(controller)
  }

  static func presentOriginalInPhotos(localIdentifier: String) {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .any(of: [.images, .livePhotos, .videos])
    configuration.selectionLimit = 1
    configuration.preselectedAssetIdentifiers = [localIdentifier]
    present(PHPickerViewController(configuration: configuration))
  }

  private static func present(_ controller: UIViewController) {
    guard let presenter = presentationController else { return }
    if let popover = controller.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(
        x: presenter.view.bounds.midX,
        y: presenter.view.bounds.maxY - 80,
        width: 1,
        height: 1
      )
    }
    presenter.present(controller, animated: true)
  }

  private static var presentationController: UIViewController? {
    var controller = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
      .first
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}
