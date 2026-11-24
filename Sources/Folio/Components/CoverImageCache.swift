import AppKit
import FolioCore
import Foundation

/// 并发安全的电子书封面内存缓存与代理加载器
actor CoverImageCache {
    static let shared = CoverImageCache()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 240
        return c
    }()

    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var proxy: ProxyConfiguration = .systemDefault
    private var urlSession: URLSession = ProxySessionFactory.makeSession(
        proxy: .systemDefault,
        timeoutInterval: 15,
        resourceTimeout: 30
    )

    func updateProxy(_ newProxy: ProxyConfiguration) {
        guard newProxy != proxy else { return }
        proxy = newProxy
        urlSession.finishTasksAndInvalidate()
        urlSession = ProxySessionFactory.makeSession(
            proxy: newProxy,
            timeoutInterval: 15,
            resourceTimeout: 30
        )
    }

    func image(for urlString: String) async -> NSImage? {
        guard !urlString.isEmpty, let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            return nil
        }
        let key = urlString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let existingTask = inFlight[urlString] {
            return await existingTask.value
        }

        let session = self.urlSession
        let task = Task<NSImage?, Never> {
            var request = URLRequest(url: url)
            request.setValue(EapiHeaders.userAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = NSImage(data: data) else {
                return nil
            }
            return image
        }

        inFlight[urlString] = task
        let image = await task.value
        inFlight.removeValue(forKey: urlString)
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }
}
