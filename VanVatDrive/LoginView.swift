import SwiftUI
import VanVatDriveKit

@MainActor struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var identifier = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "externaldrive.fill.badge.icloud")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                    .padding(.top, 60)
                Text("Van Vat Drive").font(.largeTitle.bold())
                Text("Sign in with your Van Vat account").foregroundStyle(.secondary)

                if let notice = model.notice {
                    Text(notice).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    if !needsCode {
                        TextField("Email or username", text: $identifier)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding(12)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text("Two-step verification").font(.headline)
                        Text("Enter the code from your authenticator app, the code we emailed you, or a recovery code.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        TextField("Code", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }

                Button(action: submit) {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(needsCode ? "Verify" : "Sign in").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || (needsCode ? code.trimmingCharacters(in: .whitespaces).isEmpty : identifier.isEmpty || password.isEmpty))

                if needsCode {
                    Button("Back") { needsCode = false; code = ""; error = nil }.font(.footnote)
                }
            }
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func submit() {
        Task {
            busy = true
            error = nil
            defer { busy = false }
            do {
                if needsCode {
                    let result = try await model.account.verifyTwoFactor(code: code.trimmingCharacters(in: .whitespaces))
                    await model.didSignIn(token: result.token)
                } else {
                    switch try await model.account.login(identifier: identifier.trimmingCharacters(in: .whitespaces), password: password) {
                    case .signedIn(let token, _): await model.didSignIn(token: token)
                    case .needsTwoFactor: needsCode = true
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
