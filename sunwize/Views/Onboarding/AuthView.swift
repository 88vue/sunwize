import SwiftUI
import AuthenticationServices

struct AuthView: View {
    let onSuccess: (String) -> Void
    let onBack: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""
    @State private var isSignUp = false
    @State private var showError = false
    @State private var errorMessage = ""

    @EnvironmentObject var authService: AuthenticationService
    @FocusState private var focusedField: Field?

    enum Field {
        case email, password, confirmPassword, name
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)

                    Text(isSignUp ? "Create Account" : "Welcome Back")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(isSignUp ? "Sign up to get started" : "Sign in to continue")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                // OAuth buttons
                VStack(spacing: 16) {
                    SignInWithAppleButton()
                        .frame(height: 50)
                        .cornerRadius(12)

                    GoogleSignInButton {
                        // Handle Google Sign In
                        // Implementation would use Google Sign-In SDK
                    }
                }
                .padding(.horizontal, 20)

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)

                    Text("OR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)

                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal, 20)

                // Email/Password form
                VStack(spacing: 16) {
                    if isSignUp {
                        CustomTextField(
                            placeholder: "Full Name",
                            text: $name,
                            icon: "person.fill"
                        )
                        .focused($focusedField, equals: .name)
                    }

                    CustomTextField(
                        placeholder: "Email",
                        text: $email,
                        icon: "envelope.fill",
                        keyboardType: .emailAddress
                    )
                    .focused($focusedField, equals: .email)
                    .autocapitalization(.none)

                    CustomSecureField(
                        placeholder: "Password",
                        text: $password,
                        icon: "lock.fill"
                    )
                    .focused($focusedField, equals: .password)

                    if isSignUp {
                        CustomSecureField(
                            placeholder: "Confirm Password",
                            text: $confirmPassword,
                            icon: "lock.fill"
                        )
                        .focused($focusedField, equals: .confirmPassword)
                    }
                }
                .padding(.horizontal, 20)

                // Submit button
                Button(action: handleSubmit) {
                    if authService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(isSignUp ? "Sign Up" : "Sign In")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.orange)
                .cornerRadius(12)
                .disabled(authService.isLoading)
                .padding(.horizontal, 20)

                // Toggle sign up/sign in
                Button(action: { isSignUp.toggle() }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }

                // Back button
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Back")
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
                .padding(.bottom, 40)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: authService.errorMessage) { _, newValue in
            if let error = newValue {
                errorMessage = error
                showError = true
            }
        }
    }

    private func handleSubmit() {
        // Validate input
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            showError = true
            return
        }

        if isSignUp {
            guard !name.isEmpty else {
                errorMessage = "Please enter your name"
                showError = true
                return
            }

            guard password == confirmPassword else {
                errorMessage = "Passwords don't match"
                showError = true
                return
            }

            guard password.count >= 6 else {
                errorMessage = "Password must be at least 6 characters"
                showError = true
                return
            }
        }

        Task {
            do {
                if isSignUp {
                    try await authService.signUp(email: email, password: password, name: name)
                } else {
                    try await authService.signIn(email: email, password: password)
                }
                onSuccess(email)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Custom Text Field
struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Custom Secure Field
struct CustomSecureField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .frame(width: 20)

            SecureField(placeholder, text: $text)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Google Sign In Button
struct GoogleSignInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "globe")
                    .font(.title3)
                Text("Sign in with Google")
                    .font(.headline)
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}