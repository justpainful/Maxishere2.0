import Foundation

actor MaxAPIClient {
  private var baseURL: URL
  private var bearerToken: String?
  private let session: URLSession
  private let decoder: JSONDecoder

  init(baseURL: URL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  func updateBaseURL(_ url: URL) {
    baseURL = url
  }

  func setBearerToken(_ token: String?) {
    bearerToken = token
  }

  func healthCheck() async throws -> Bool {
    let response: APIHealthResponse = try await request(path: "/health", method: "GET")
    return response.status.lowercased() == "ok"
  }

  func signIn(email: String, password: String) async throws -> String {
    let payload = SignInRequest(email: email, password: password)
    let response: SignInResponse = try await request(
      path: "/api/v2/auth/login",
      method: "POST",
      body: payload
    )
    bearerToken = response.accessToken
    return response.accessToken
  }

  private func request<Response: Decodable & Sendable>(
    path: String,
    method: String
  ) async throws -> Response {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let bearerToken {
      request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }
    return try await perform(request)
  }

  private func request<Body: Encodable & Sendable, Response: Decodable & Sendable>(
    path: String,
    method: String,
    body: Body
  ) async throws -> Response {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    if let bearerToken {
      request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }
    return try await perform(request)
  }

  private func perform<Response: Decodable & Sendable>(_ request: URLRequest) async throws -> Response {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw MaxAPIClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      throw MaxAPIClientError.httpStatus(http.statusCode)
    }
    return try decoder.decode(Response.self, from: data)
  }
}

private struct SignInRequest: Encodable, Sendable {
  let email: String
  let password: String
}

private struct SignInResponse: Decodable, Sendable {
  let accessToken: String

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
  }
}

private struct APIHealthResponse: Decodable, Sendable {
  let status: String
}

enum MaxAPIClientError: Error, LocalizedError, Sendable {
  case invalidResponse
  case httpStatus(Int)

  var errorDescription: String? {
    switch self {
    case .invalidResponse: "The server returned an invalid response."
    case .httpStatus(let code): "The server returned HTTP \(code)."
    }
  }
}

