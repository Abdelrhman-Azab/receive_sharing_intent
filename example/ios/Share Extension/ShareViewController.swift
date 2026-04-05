import UIKit
import Social
import Photos
import AVFoundation
import UniformTypeIdentifiers
import MobileCoreServices

private let kSchemePrefix = "ShareMedia"
private let kUserDefaultsKey = "ShareKey"
private let kUserDefaultsMessageKey = "ShareMessageKey"
private let kAppGroupIdKey = "AppGroupId"

private enum SharedMediaType: String, Codable, CaseIterable {
    case image
    case video
    case text
    case file
    case url

    var toUTTypeIdentifier: String {
        if #available(iOS 14.0, *) {
            switch self {
            case .image:
                return UTType.image.identifier
            case .video:
                return UTType.movie.identifier
            case .text:
                return UTType.text.identifier
            case .file:
                return UTType.fileURL.identifier
            case .url:
                return UTType.url.identifier
            }
        }
        switch self {
        case .image:
            return "public.image"
        case .video:
            return "public.movie"
        case .text:
            return "public.text"
        case .file:
            return "public.file-url"
        case .url:
            return "public.url"
        }
    }
}

private struct SharedMediaFile: Codable {
    let path: String
    let mimeType: String?
    let thumbnail: String?
    let duration: Double?
    let message: String?
    let type: SharedMediaType
}

class ShareViewController: SLComposeServiceViewController {
    private var hostAppBundleIdentifier = ""
    private var appGroupId = ""
    private var sharedMedia: [SharedMediaFile] = []

    override func isContentValid() -> Bool {
        true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadIds()
    }

    override func didSelectPost() {
        saveAndRedirect(message: contentText)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let extensionContext,
              let content = extensionContext.inputItems.first as? NSExtensionItem,
              let contents = content.attachments else {
            dismissWithError()
            return
        }

        for (index, attachment) in contents.enumerated() {
            for type in SharedMediaType.allCases where attachment.hasItemConformingToTypeIdentifier(type.toUTTypeIdentifier) {
                attachment.loadItem(forTypeIdentifier: type.toUTTypeIdentifier) { [weak self] data, error in
                    guard let self, error == nil else {
                        self?.dismissWithError()
                        return
                    }
                    switch type {
                    case .text:
                        if let text = data as? String {
                            self.handleMedia(forLiteral: text, type: type, index: index, content: content)
                        }
                    case .url:
                        if let url = data as? URL {
                            self.handleMedia(forLiteral: url.absoluteString, type: type, index: index, content: content)
                        }
                    default:
                        if let url = data as? URL {
                            self.handleMedia(forFile: url, type: type, index: index, content: content)
                        } else if let image = data as? UIImage {
                            self.handleMedia(forUIImage: image, type: type, index: index, content: content)
                        }
                    }
                }
                break
            }
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    override func presentationAnimationDidFinish() {
        super.presentationAnimationDidFinish()
        navigationController?.navigationBar.topItem?.rightBarButtonItem?.title = "Send"
    }

    private func shouldAutoRedirect() -> Bool {
        false
    }

    private func loadIds() {
        guard let shareExtensionAppBundleIdentifier = Bundle.main.bundleIdentifier,
              let lastIndexOfPoint = shareExtensionAppBundleIdentifier.lastIndex(of: ".") else {
            return
        }
        hostAppBundleIdentifier = String(shareExtensionAppBundleIdentifier[..<lastIndexOfPoint])
        let defaultAppGroupId = "group.\(hostAppBundleIdentifier)"
        let customAppGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        appGroupId = customAppGroupId ?? defaultAppGroupId
    }

    private func handleMedia(forLiteral item: String, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        sharedMedia.append(SharedMediaFile(path: item, mimeType: type == .text ? "text/plain" : nil, thumbnail: nil, duration: nil, message: nil, type: type))
        if index == (content.attachments?.count ?? 0) - 1, shouldAutoRedirect() {
            saveAndRedirect()
        }
    }

    private func handleMedia(forUIImage image: UIImage, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            dismissWithError()
            return
        }
        let tempPath = containerURL.appendingPathComponent("TempImage.png")
        if writeTempFile(image, to: tempPath) {
            let newPathDecoded = tempPath.absoluteString.removingPercentEncoding ?? tempPath.path
            sharedMedia.append(SharedMediaFile(path: newPathDecoded, mimeType: type == .image ? "image/png" : nil, thumbnail: nil, duration: nil, message: nil, type: type))
        }
        if index == (content.attachments?.count ?? 0) - 1, shouldAutoRedirect() {
            saveAndRedirect()
        }
    }

    private func handleMedia(forFile url: URL, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            dismissWithError()
            return
        }
        let fileName = getFileName(from: url, type: type)
        let newPath = containerURL.appendingPathComponent(fileName)

        if copyFile(at: url, to: newPath) {
            let newPathDecoded = newPath.absoluteString.removingPercentEncoding ?? newPath.path
            if type == .video, let videoInfo = getVideoInfo(from: url) {
                let thumbnailPathDecoded = videoInfo.thumbnail?.removingPercentEncoding
                sharedMedia.append(SharedMediaFile(path: newPathDecoded, mimeType: url.mimeType(), thumbnail: thumbnailPathDecoded, duration: videoInfo.duration, message: nil, type: type))
            } else {
                sharedMedia.append(SharedMediaFile(path: newPathDecoded, mimeType: url.mimeType(), thumbnail: nil, duration: nil, message: nil, type: type))
            }
        }

        if index == (content.attachments?.count ?? 0) - 1, shouldAutoRedirect() {
            saveAndRedirect()
        }
    }

    private func saveAndRedirect(message: String? = nil) {
        let userDefaults = UserDefaults(suiteName: appGroupId)
        userDefaults?.set(toData(data: sharedMedia), forKey: kUserDefaultsKey)
        userDefaults?.set(message, forKey: kUserDefaultsMessageKey)
        userDefaults?.synchronize()
        redirectToHostApp()
    }

    private func redirectToHostApp() {
        loadIds()
        guard let url = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share") else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }
        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func dismissWithError() {
        let alert = UIAlertController(title: "Error", message: "Error loading data", preferredStyle: .alert)
        let action = UIAlertAction(title: "Error", style: .cancel) { _ in
            self.dismiss(animated: true, completion: nil)
        }
        alert.addAction(action)
        present(alert, animated: true, completion: nil)
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func getFileName(from url: URL, type: SharedMediaType) -> String {
        var name = url.lastPathComponent
        if name.isEmpty {
            switch type {
            case .image:
                name = UUID().uuidString + ".png"
            case .video:
                name = UUID().uuidString + ".mp4"
            case .text:
                name = UUID().uuidString + ".txt"
            default:
                name = UUID().uuidString
            }
        }
        return name
    }

    private func writeTempFile(_ image: UIImage, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try image.pngData()?.write(to: dstURL)
            return true
        } catch {
            return false
        }
    }

    private func copyFile(at srcURL: URL, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            return true
        } catch {
            return false
        }
    }

    private func getVideoInfo(from url: URL) -> (thumbnail: String?, duration: Double)? {
        let asset = AVAsset(url: url)
        let duration = (CMTimeGetSeconds(asset.duration) * 1000).rounded()
        guard let thumbnailPath = getThumbnailPath(for: url) else {
            return nil
        }

        if FileManager.default.fileExists(atPath: thumbnailPath.path) {
            return (thumbnail: thumbnailPath.absoluteString, duration: duration)
        }

        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        assetImgGenerate.maximumSize = CGSize(width: 360, height: 360)
        do {
            let img = try assetImgGenerate.copyCGImage(at: CMTimeMakeWithSeconds(600, preferredTimescale: 1), actualTime: nil)
            try UIImage(cgImage: img).pngData()?.write(to: thumbnailPath)
            return (thumbnail: thumbnailPath.absoluteString, duration: duration)
        } catch {
            return nil
        }
    }

    private func getThumbnailPath(for url: URL) -> URL? {
        let fileName = Data(url.lastPathComponent.utf8).base64EncodedString().replacingOccurrences(of: "==", with: "")
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return nil
        }
        return containerURL.appendingPathComponent("\(fileName).jpg")
    }

    private func toData(data: [SharedMediaFile]) -> Data {
        let encodedData = try? JSONEncoder().encode(data)
        return encodedData ?? Data()
    }
}

private extension URL {
    func mimeType() -> String {
        if #available(iOS 14.0, *) {
            if let mimeType = UTType(filenameExtension: self.pathExtension)?.preferredMIMEType {
                return mimeType
            }
        } else {
            if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, self.pathExtension as NSString, nil)?.takeRetainedValue(),
               let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimetype as String
            }
        }
        return "application/octet-stream"
    }
}
