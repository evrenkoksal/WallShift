import Foundation

/// Fetches candidate wallpapers from one website.
protocol ImageSourceProvider {
    var kind: SourceKind { get }
    func fetchCandidates(prefs: Preferences) async throws -> [RemoteImage]
}

enum Net {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static let userAgent = "WallShift/1.0 (macOS; +https://github.com/wallshift)"

    static func data(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WallShiftError.badResponse(http.statusCode)
        }
        return data
    }

    static func json(from url: URL, headers: [String: String] = [:]) async throws -> Any {
        let data = try await data(from: url, headers: headers)
        return try JSONSerialization.jsonObject(with: data)
    }
}

// MARK: - Bing

struct BingSource: ImageSourceProvider {
    let kind = SourceKind.bing

    func fetchCandidates(prefs: Preferences) async throws -> [RemoteImage] {
        let market = prefs.bingMarket.isEmpty ? "en-US" : prefs.bingMarket
        let url = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=\(market)")!
        guard let root = try await Net.json(from: url) as? [String: Any],
              let images = root["images"] as? [[String: Any]] else {
            throw WallShiftError.sourceFailed(kind, "beklenmeyen yanıt")
        }
        return images.compactMap { image in
            // urlbase gives us the raw id, from which the UHD variant can be built.
            guard let base = image["urlbase"] as? String,
                  let full = URL(string: "https://www.bing.com\(base)_UHD.jpg") else { return nil }
            let copyright = image["copyright"] as? String
            let page = (image["copyrightlink"] as? String).flatMap(URL.init(string:))
            return RemoteImage(imageURL: full, source: kind, title: copyright, pageURL: page, credit: "Bing")
        }
    }
}

// MARK: - Wallhaven

struct WallhavenSource: ImageSourceProvider {
    let kind = SourceKind.wallhaven

    func fetchCandidates(prefs: Preferences) async throws -> [RemoteImage] {
        var categories = ""
        categories += prefs.wallhavenGeneral ? "1" : "0"
        categories += prefs.wallhavenAnime ? "1" : "0"
        categories += prefs.wallhavenPeople ? "1" : "0"
        if categories == "000" { categories = "100" }

        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        var items = [
            URLQueryItem(name: "categories", value: categories),
            URLQueryItem(name: "purity", value: "100"), // SFW only
            URLQueryItem(name: "sorting", value: "random"),
            URLQueryItem(name: "atleast", value: "\(prefs.minWidth)x\(prefs.minHeight)"),
        ]
        let query = prefs.wallhavenQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        let ratios = prefs.wallhavenRatios.trimmingCharacters(in: .whitespaces)
        if !ratios.isEmpty { items.append(URLQueryItem(name: "ratios", value: ratios)) }
        components.queryItems = items

        var headers: [String: String] = [:]
        let key = prefs.wallhavenAPIKey.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { headers["X-API-Key"] = key }

        guard let root = try await Net.json(from: components.url!, headers: headers) as? [String: Any],
              let data = root["data"] as? [[String: Any]] else {
            throw WallShiftError.sourceFailed(kind, "beklenmeyen yanıt")
        }
        return data.compactMap { item in
            guard let path = item["path"] as? String, let imageURL = URL(string: path) else { return nil }
            let page = (item["url"] as? String).flatMap(URL.init(string:))
            let width = item["dimension_x"] as? Int ?? 0
            let height = item["dimension_y"] as? Int ?? 0
            if width > 0, width < prefs.minWidth || height < prefs.minHeight { return nil }
            return RemoteImage(imageURL: imageURL, source: kind,
                               title: query.isEmpty ? "Wallhaven" : "Wallhaven · \(query)",
                               pageURL: page, credit: "wallhaven.cc")
        }
    }
}

// MARK: - Reddit

struct RedditSource: ImageSourceProvider {
    let kind = SourceKind.reddit

    func fetchCandidates(prefs: Preferences) async throws -> [RemoteImage] {
        let subs = prefs.redditSubreddits
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " /r")) }
            .filter { !$0.isEmpty }
        guard !subs.isEmpty else { throw WallShiftError.sourceFailed(kind, "subreddit listesi boş") }

        var results: [RemoteImage] = []
        var lastError: Error?
        for sub in subs {
            do {
                // Reddit blocks the anonymous .json API, but the RSS feed stays open.
                let url = URL(string: "https://www.reddit.com/r/\(sub)/top.rss?t=\(prefs.redditTimeframe)")!
                let data = try await Net.data(from: url)
                guard let feed = String(data: data, encoding: .utf8) else { continue }
                results.append(contentsOf: Self.parse(feed: feed, sub: sub, kind: kind))
            } catch {
                lastError = Self.friendlyError(error, kind: kind)
            }
        }
        if results.isEmpty {
            throw lastError ?? WallShiftError.sourceFailed(kind, "feed'de görsel bulunamadı")
        }
        return results
    }

    private static func friendlyError(_ error: Error, kind: SourceKind) -> Error {
        if case let WallShiftError.badResponse(code) = error, code == 403 || code == 429 {
            return WallShiftError.sourceFailed(kind, "Reddit isteği reddetti (\(code)); anonim erişim kısıtlı, bir süre sonra tekrar denenecek")
        }
        return error
    }

    /// Pulls the direct i.redd.it image out of each Atom entry.
    private static func parse(feed: String, sub: String, kind: SourceKind) -> [RemoteImage] {
        var images: [RemoteImage] = []
        let entries = feed.components(separatedBy: "<entry>").dropFirst()
        for entry in entries {
            guard let raw = firstMatch(in: entry,
                                       pattern: "https://i\\.redd\\.it/[A-Za-z0-9._-]+\\.(?:jpg|jpeg|png)"),
                  let imageURL = URL(string: raw) else { continue }
            let title = firstMatch(in: entry, pattern: "<title>(.*?)</title>", group: 1)?
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
            let permalink = firstMatch(in: entry, pattern: "<link href=\"([^\"]+)\"", group: 1)
                .flatMap(URL.init(string:))
            images.append(RemoteImage(imageURL: imageURL, source: kind, title: title,
                                      pageURL: permalink, credit: "r/\(sub)"))
        }
        return images
    }

    private static func firstMatch(in text: String, pattern: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }
}

// MARK: - Wikimedia Commons

struct WikimediaSource: ImageSourceProvider {
    let kind = SourceKind.wikimedia

    func fetchCandidates(prefs: Preferences) async throws -> [RemoteImage] {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        // The category is alphabetical, so start at a random prefix for variety.
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        let prefix = String(alphabet.randomElement()!)
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "categorymembers"),
            URLQueryItem(name: "gcmtitle", value: "Category:\(prefs.wikimediaCategory)"),
            URLQueryItem(name: "gcmtype", value: "file"),
            URLQueryItem(name: "gcmlimit", value: "60"),
            URLQueryItem(name: "gcmstartsortkeyprefix", value: prefix),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|size"),
            URLQueryItem(name: "iiurlwidth", value: "3840"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let root = try await Net.json(from: components.url!) as? [String: Any],
              let query = root["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any] else {
            throw WallShiftError.sourceFailed(kind, "beklenmeyen yanıt")
        }
        return pages.values.compactMap { value in
            guard let page = value as? [String: Any],
                  let info = (page["imageinfo"] as? [[String: Any]])?.first,
                  let thumb = info["thumburl"] as? String,
                  let imageURL = URL(string: thumb) else { return nil }
            let width = info["thumbwidth"] as? Int ?? info["width"] as? Int ?? 0
            let height = info["thumbheight"] as? Int ?? info["height"] as? Int ?? 0
            // Wallpapers should be landscape and big enough for the screen.
            guard width >= height, width >= prefs.minWidth, height >= prefs.minHeight else { return nil }
            let title = (page["title"] as? String)?
                .replacingOccurrences(of: "File:", with: "")
                .replacingOccurrences(of: "_", with: " ")
            let descriptionPage = (info["descriptionurl"] as? String).flatMap(URL.init(string:))
            return RemoteImage(imageURL: imageURL, source: kind, title: title,
                               pageURL: descriptionPage, credit: "Wikimedia Commons")
        }
    }
}

// MARK: - Unsplash

struct UnsplashSource: ImageSourceProvider {
    let kind = SourceKind.unsplash

    func fetchCandidates(prefs: Preferences) async throws -> [RemoteImage] {
        let key = prefs.unsplashAccessKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw WallShiftError.sourceFailed(kind, "Access Key girilmemiş") }

        var components = URLComponents(string: "https://api.unsplash.com/photos/random")!
        var items = [
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "orientation", value: "landscape"),
        ]
        let query = prefs.unsplashQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
        components.queryItems = items

        let headers = ["Authorization": "Client-ID \(key)", "Accept-Version": "v1"]
        guard let list = try await Net.json(from: components.url!, headers: headers) as? [[String: Any]] else {
            throw WallShiftError.sourceFailed(kind, "beklenmeyen yanıt (anahtar geçersiz olabilir)")
        }
        return list.compactMap { photo in
            guard let urls = photo["urls"] as? [String: Any] else { return nil }
            // `raw` lets us request an exact width; fall back to the prepared `full`.
            let candidate: String?
            if let raw = urls["raw"] as? String {
                candidate = raw + "&w=3840&q=85&fm=jpg"
            } else {
                candidate = urls["full"] as? String
            }
            guard let candidate, let imageURL = URL(string: candidate) else { return nil }
            let user = (photo["user"] as? [String: Any])?["name"] as? String
            let page = ((photo["links"] as? [String: Any])?["html"] as? String).flatMap(URL.init(string:))
            return RemoteImage(imageURL: imageURL, source: kind,
                               title: photo["description"] as? String ?? photo["alt_description"] as? String,
                               pageURL: page,
                               credit: user.map { "\($0) / Unsplash" } ?? "Unsplash")
        }
    }
}

// MARK: - NASA APOD

struct NASASource: ImageSourceProvider {
    let kind = SourceKind.nasa

    func fetchCandidates(prefs: Preferences) async throws -> [RemoteImage] {
        let key = prefs.nasaAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
            ? "DEMO_KEY" : prefs.nasaAPIKey.trimmingCharacters(in: .whitespaces)
        let url = URL(string: "https://api.nasa.gov/planetary/apod?api_key=\(key)&count=10&thumbs=false")!
        guard let list = try await Net.json(from: url) as? [[String: Any]] else {
            throw WallShiftError.sourceFailed(kind, "beklenmeyen yanıt (DEMO_KEY kotası dolmuş olabilir)")
        }
        return list.compactMap { item in
            guard item["media_type"] as? String == "image" else { return nil }
            let candidate = (item["hdurl"] as? String) ?? (item["url"] as? String)
            guard let candidate, let imageURL = URL(string: candidate) else { return nil }
            let page = (item["date"] as? String).flatMap { date -> URL? in
                let compact = date.replacingOccurrences(of: "-", with: "")
                let short = String(compact.dropFirst(2))
                return URL(string: "https://apod.nasa.gov/apod/ap\(short).html")
            }
            return RemoteImage(imageURL: imageURL, source: kind,
                               title: item["title"] as? String,
                               pageURL: page,
                               credit: item["copyright"] as? String ?? "NASA APOD")
        }
    }
}

// MARK: - Lorem Picsum

struct PicsumSource: ImageSourceProvider {
    let kind = SourceKind.picsum

    func fetchCandidates(prefs: Preferences) async throws -> [RemoteImage] {
        // Picsum has no search API; ask for a handful of distinct random seeds.
        let width = max(prefs.minWidth, 1920)
        let height = max(prefs.minHeight, 1080)
        return (0..<8).compactMap { _ in
            let seed = UUID().uuidString.prefix(8)
            guard let url = URL(string: "https://picsum.photos/seed/\(seed)/\(width)/\(height)") else { return nil }
            return RemoteImage(imageURL: url, source: kind, title: "Picsum · \(seed)",
                               pageURL: URL(string: "https://picsum.photos"), credit: "Lorem Picsum")
        }
    }
}

// MARK: - Custom URLs

struct CustomSource: ImageSourceProvider {
    let kind = SourceKind.custom

    func fetchCandidates(prefs: Preferences) async throws -> [RemoteImage] {
        let urls = prefs.customURLs
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap(URL.init(string:))
        guard !urls.isEmpty else { throw WallShiftError.sourceFailed(kind, "URL listesi boş") }
        return urls.map {
            RemoteImage(imageURL: $0, source: kind, title: $0.lastPathComponent,
                        pageURL: $0, credit: $0.host)
        }
    }
}

enum SourceRegistry {
    static func provider(for kind: SourceKind) -> ImageSourceProvider {
        switch kind {
        case .bing: return BingSource()
        case .wallhaven: return WallhavenSource()
        case .reddit: return RedditSource()
        case .unsplash: return UnsplashSource()
        case .nasa: return NASASource()
        case .picsum: return PicsumSource()
        case .wikimedia: return WikimediaSource()
        case .custom: return CustomSource()
        }
    }
}
