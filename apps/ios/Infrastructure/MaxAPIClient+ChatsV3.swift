import Foundation

extension MaxAPIClient {
  func deleteChat(chatID: String) async throws -> EmptySuccess {
    try await MaxChatsV3Transport.request(
      path: "/api/v2/conversations/\(MaxChatsV3Transport.encoded(chatID))",
      method: "DELETE"
    )
  }

  func clearChatMessages(chatID: String) async throws -> EmptySuccess {
    try await MaxChatsV3Transport.request(
      path: "/api/v2/conversations/\(MaxChatsV3Transport.encoded(chatID))/messages",
      method: "DELETE"
    )
  }

  func readViewOnceMessage(chatID: String, messageID: String) async throws -> EmptySuccess {
    try await MaxChatsV3Transport.request(
      path: "/api/v2/conversations/\(MaxChatsV3Transport.encoded(chatID))/messages/\(MaxChatsV3Transport.encoded(messageID))/read",
      method: "POST"
    )
  }

  func sendImageMessage(
    chatID: String,
    imageData: Data,
    replyToID: String?,
    isViewOnce: Bool
  ) async throws -> MobileMessageSendResponse {
    try await MaxChatsV3Transport.uploadImage(
      chatID: chatID,
      imageData: imageData,
      replyToID: replyToID,
      isViewOnce: isViewOnce
    )
  }

  func sendVoiceMessage(
    chatID: String,
    audioData: Data,
    replyToID: String?
  ) async throws -> MobileMessageSendResponse {
    try await MaxChatsV3Transport.uploadVoice(
      chatID: chatID,
      audioData: audioData,
      replyToID: replyToID
    )
  }

  func createSticker(
    imageData: Data,
    mimeType: String,
    emoji: String?
  ) async throws -> MaxSticker {
    try await MaxChatsV3Transport.uploadSticker(
      imageData: imageData,
      mimeType: mimeType,
      emoji: emoji
    )
  }
}

private enum MaxChatsV3Transport {
  private static let maximumImageBytes = 12 * 1_024 * 1_024

  static func uploadVoice(
    chatID: String,
    audioData: Data,
    replyToID: String?
  ) async throws -> MobileMessageSendResponse {
    guard !audioData.isEmpty, audioData.count <= maximumImageBytes else {
      throw MaxAPIError.server(
        status: 413,
        message: String(localized: "upload.error.too_large")
      )
    }

    let boundary = "MaxChatsV3-\(UUID().uuidString)"
    var body = Data()

    if let replyToID, !replyToID.isEmpty {
      body.appendMultipartField(name: "replyToId", value: replyToID, boundary: boundary)
    }
    body.appendMultipartFile(
      name: "file",
      fileName: "voice.m4a",
      mimeType: "audio/m4a",
      bytes: audioData,
      boundary: boundary
    )
    body.append(Data("--\(boundary)--\r\n".utf8))

    var request = try makeRequest(
      path: "/api/v2/conversations/\(encoded(chatID))/voice",
      method: "POST"
    )
    request.timeoutInterval = 90
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type"
    )
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response: response, data: data)
    return try JSONDecoder().decode(MobileMessageSendResponse.self, from: data)
  }

  static func request<Response: Decodable>(path: String, method: String) async throws -> Response {
    var request = try makeRequest(path: path, method: method)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response: response, data: data)
    // A 204 (or any empty 2xx) is a success, not a payload. Decoding zero bytes
    // threw and made every successful delete look like a failure to the caller.
    if data.isEmpty || (response as? HTTPURLResponse)?.statusCode == 204 {
      if let empty = EmptySuccess(success: true) as? Response { return empty }
      throw MaxAPIError.invalidResponse
    }
    return try JSONDecoder().decode(Response.self, from: data)
  }

  static func uploadImage(
    chatID: String,
    imageData: Data,
    replyToID: String?,
    isViewOnce: Bool
  ) async throws -> MobileMessageSendResponse {
    guard !imageData.isEmpty, imageData.count <= maximumImageBytes else {
      let message = imageData.isEmpty
        ? String(localized: "error.upload.failed")
        : String(localized: "upload.error.too_large")
      throw MaxAPIError.server(status: 413, message: message)
    }

    let boundary = "MaxChatsV3-\(UUID().uuidString)"
    var body = Data()

    if let replyToID, !replyToID.isEmpty {
      body.appendMultipartField(name: "replyToId", value: replyToID, boundary: boundary)
    }
    if isViewOnce {
      body.appendMultipartField(name: "isViewOnce", value: "true", boundary: boundary)
    }
    body.appendMultipartFile(
      name: "file",
      fileName: "chat-image.jpg",
      mimeType: "image/jpeg",
      bytes: imageData,
      boundary: boundary
    )
    body.append(Data("--\(boundary)--\r\n".utf8))

    var request = try makeRequest(
      path: "/api/v2/conversations/\(encoded(chatID))/images",
      method: "POST"
    )
    request.timeoutInterval = 90
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type"
    )
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response: response, data: data)
    return try JSONDecoder().decode(MobileMessageSendResponse.self, from: data)
  }

  /// Uploads a sticker image (caller already downscaled it to ≤512 px). The
  /// endpoint answers with the sticker row itself, not a message envelope.
  static func uploadSticker(
    imageData: Data,
    mimeType: String,
    emoji: String?
  ) async throws -> MaxSticker {
    // The server caps a sticker at 4 MB; a 512 px JPEG is far below it, so a
    // violation here means the caller skipped the downscale.
    guard !imageData.isEmpty, imageData.count <= 4 * 1_024 * 1_024 else {
      let message = imageData.isEmpty
        ? String(localized: "error.upload.failed")
        : String(localized: "upload.error.too_large")
      throw MaxAPIError.server(status: 413, message: message)
    }

    let boundary = "MaxChatsV3-\(UUID().uuidString)"
    var body = Data()

    if let emoji, !emoji.isEmpty {
      body.appendMultipartField(name: "emoji", value: emoji, boundary: boundary)
    }
    let fileName = mimeType.lowercased() == "image/png" ? "sticker.png" : "sticker.jpg"
    body.appendMultipartFile(
      name: "file",
      fileName: fileName,
      mimeType: mimeType,
      bytes: imageData,
      boundary: boundary
    )
    body.append(Data("--\(boundary)--\r\n".utf8))

    var request = try makeRequest(path: "/api/v2/stickers", method: "POST")
    request.timeoutInterval = 90
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type"
    )
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response: response, data: data)
    return try JSONDecoder().decode(MaxSticker.self, from: data)
  }

  static func encoded(_ value: String) -> String {
    let unreserved = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
    return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
  }

  private static func makeRequest(path: String, method: String) throws -> URLRequest {
    let configuration = MaxConfiguration.fromBundle()
    guard path.hasPrefix("/"),
          !path.hasPrefix("//"),
          let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL,
          MaxConfiguration.isValidRemoteMediaURL(url) else {
      throw MaxAPIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 45
    request.setValue(
      configuration.baseURL.absoluteString,
      forHTTPHeaderField: "X-Max-Public-Origin"
    )

    let tokenStore = KeychainSessionStore(service: "app.max.iphone")
    if let token = try tokenStore.loadToken()?.trimmingCharacters(in: .whitespacesAndNewlines),
       !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  private static func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
      throw MaxAPIError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      // The server's error envelope is always nested under `error`, so the old
      // top-level-string probe missed every time and users saw raw JSON.
      let message = MaxAPIClient.safeServerMessage(
        from: data,
        fallback: String(localized: "error.api.request_failed")
      )
      if http.statusCode == 401 || http.statusCode == 403 {
        throw MaxAPIError.unauthorized(status: http.statusCode, message: message)
      }
      throw MaxAPIError.server(status: http.statusCode, message: message)
    }
  }
}

private extension Data {
  mutating func appendMultipartField(name: String, value: String, boundary: String) {
    append(Data("--\(boundary)\r\n".utf8))
    append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
    append(Data("\(value)\r\n".utf8))
  }

  mutating func appendMultipartFile(
    name: String,
    fileName: String,
    mimeType: String,
    bytes: Data,
    boundary: String
  ) {
    append(Data("--\(boundary)\r\n".utf8))
    append(Data(
      "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".utf8
    ))
    append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    append(bytes)
    append(Data("\r\n".utf8))
  }
}
