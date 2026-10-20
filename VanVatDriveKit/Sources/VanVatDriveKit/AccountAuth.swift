import Foundation

public struct AccountUser: Decodable, Sendable, Equatable {
    public let id: String
    public let username: String?
    public let email: String?
}

public enum LoginOutcome: Sendable {
    case signedIn(token: String, user: AccountUser?)
    case needsTwoFactor
}

/// Van Vat account login for native apps. Sends `X-Vanvat-Client: native` so the backend also returns the JWT.
/// This session keeps cookies on purpose: the backend hands out a short-lived 2FA cookie between login and verify.
public final class AccountAuth: @unchecked Sendable {
    private let base: URL
    private let session: URLSession

    public init(account: URL = URL(string: "https://account.vanvatcorp.com")!) {
        self.base = account
        self.session = URLSession(configuration: .default)
    }

    private struct LoginBody: Encodable { let email: String; let password: String }
    private struct CodeBody: Encodable { let code: String }
    private struct Reply: Decodable {
        let success: Bool?
        let requires2FA: Bool?
        let token: String?
        let message: String?
        let user: AccountUser?
    }

    /// `identifier` is the email or the username.
    public func login(identifier: String, password: String) async throws -> LoginOutcome {
        let reply = try await post("/api/v2/account/login", LoginBody(email: identifier, password: password))
        if reply.requires2FA == true { return .needsTwoFactor }
        guard let token = reply.token else { throw DriveError(status: 500, message: "The server did not return a token.") }
        return .signedIn(token: token, user: reply.user)
    }

    /// TOTP code, email code or recovery code.
    public func verifyTwoFactor(code: String) async throws -> (token: String, user: AccountUser?) {
        let reply = try await post("/api/v2/2fa/verify", CodeBody(code: code))
        guard let token = reply.token else { throw DriveError(status: 500, message: "The server did not return a token.") }
        return (token, reply.user)
    }

    private func post<B: Encodable>(_ path: String, _ body: B) async throws -> Reply {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("native", forHTTPHeaderField: "X-Vanvat-Client")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        guard (200..<300).contains(status), reply?.success != false else {
            throw DriveError(status: status, message: reply?.message ?? "Sign-in failed (\(status)).")
        }
        guard let reply else { throw DriveError(status: status, message: "Unexpected server reply.") }
        return reply
    }
}
