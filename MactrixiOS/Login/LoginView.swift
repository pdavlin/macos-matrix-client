import AuthenticationServices
import SwiftUI

/// The iOS sign-in screen. Same steps as the Mac `WelcomeSheetView`: enter a
/// homeserver, discover its sign-in methods, then sign in with OIDC (browser)
/// or a password.
struct LoginView: View {
    @State private var model: LoginViewModel

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @FocusState private var focusedField: Field?

    private enum Field {
        case homeserver, username, password
    }

    init(model: LoginViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                homeserverSection

                if model.showsOidcLogin {
                    oidcSection
                }

                if model.showsPasswordLogin {
                    passwordSection
                }

                if model.hasNoSupportedMethod {
                    Section {
                        Text("This homeserver offers no sign-in method that this app supports.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("loginError")
                    }
                }
            }
            .disabled(model.isLoading)
            .navigationTitle("Sign In")
            .toolbar {
                if model.isLoading {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                    }
                }
            }
        }
    }

    private var homeserverSection: some View {
        Section {
            TextField("Homeserver", text: $model.homeserver, prompt: Text(LoginViewModel.defaultHomeserver))
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .focused($focusedField, equals: .homeserver)
                .onSubmit { Task { await model.discover() } }
                .onChange(of: model.homeserver) { model.homeserverDidChange() }
                .accessibilityIdentifier("homeserverField")

            if model.options == nil {
                Button("Continue") {
                    focusedField = nil
                    Task { await model.discover() }
                }
                .accessibilityIdentifier("continueButton")
            }
        } header: {
            Text("Homeserver")
        } footer: {
            Text("The server that holds your Matrix account, for example \(LoginViewModel.defaultHomeserver).")
        }
    }

    private var oidcSection: some View {
        Section {
            Button {
                Task { await model.signInWithOidc(using: webAuthenticationSession) }
            } label: {
                Label("Sign in with browser", systemImage: "safari")
            }
            .accessibilityIdentifier("oidcButton")
        } footer: {
            Text("Opens your homeserver's sign-in page.")
        }
    }

    private var passwordSection: some View {
        Section("Password") {
            TextField("Username", text: $model.username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .username)
                .onSubmit { focusedField = .password }
                .accessibilityIdentifier("usernameField")

            SecureField("Password", text: $model.password)
                .textContentType(.password)
                .submitLabel(.go)
                .focused($focusedField, equals: .password)
                .onSubmit { Task { await model.signInWithPassword() } }
                .accessibilityIdentifier("passwordField")

            Button("Sign In") {
                focusedField = nil
                Task { await model.signInWithPassword() }
            }
            .disabled(!model.canSubmitPassword)
            .accessibilityIdentifier("passwordSignInButton")
        }
    }
}

#Preview {
    LoginView(model: LoginViewModel(service: LoginService { _ in
        LoginOptions(
            supportsPassword: true,
            supportsOidc: true,
            signInWithPassword: { _, _ in },
            signInWithOidc: { _ in }
        )
    }))
}
