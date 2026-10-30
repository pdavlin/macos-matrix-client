@testable import MactrixiOS
import XCTest

/// MATRIX-83: the iOS sign-in form, driven through a fake `LoginService`.
@MainActor
final class LoginViewModelTests: XCTestCase {
    private struct TestError: LocalizedError {
        let errorDescription: String?
    }

    /// Records the calls the view model makes into the login service.
    @MainActor
    private final class Recorder {
        var discovered: [String] = []
        var passwordSignIns: [(String, String)] = []
    }

    private func makeModel(
        recorder: Recorder = Recorder(),
        supportsPassword: Bool = true,
        supportsOidc: Bool = false,
        discoverError: Error? = nil,
        signInError: Error? = nil
    ) -> LoginViewModel {
        LoginViewModel(service: LoginService { homeserver in
            recorder.discovered.append(homeserver)
            if let discoverError { throw discoverError }
            return LoginOptions(
                supportsPassword: supportsPassword,
                supportsOidc: supportsOidc,
                signInWithPassword: { username, password in
                    recorder.passwordSignIns.append((username, password))
                    if let signInError { throw signInError }
                },
                signInWithOidc: { _ in }
            )
        })
    }

    func testEmptyHomeserverFallsBackToDefault() {
        let model = makeModel()

        XCTAssertEqual(model.effectiveHomeserver, "matrix.org")

        model.homeserver = "  davlin.io \n"
        XCTAssertEqual(model.effectiveHomeserver, "davlin.io")
    }

    func testDiscoverShowsTheOfferedMethods() async {
        let recorder = Recorder()
        let model = makeModel(recorder: recorder, supportsPassword: true, supportsOidc: true)
        model.homeserver = "example.org"

        await model.discover()

        XCTAssertEqual(recorder.discovered, ["example.org"])
        XCTAssertTrue(model.showsPasswordLogin)
        XCTAssertTrue(model.showsOidcLogin)
        XCTAssertFalse(model.hasNoSupportedMethod)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testDiscoverWithNoSupportedMethodSaysSo() async {
        let model = makeModel(supportsPassword: false, supportsOidc: false)

        await model.discover()

        XCTAssertTrue(model.hasNoSupportedMethod)
        XCTAssertFalse(model.showsPasswordLogin)
        XCTAssertFalse(model.showsOidcLogin)
    }

    func testDiscoverFailureShowsTheErrorAndNoMethods() async {
        let model = makeModel(discoverError: TestError(errorDescription: "Server unreachable"))

        await model.discover()

        XCTAssertNil(model.options)
        XCTAssertEqual(model.errorMessage, "Server unreachable")
        XCTAssertFalse(model.isLoading)
    }

    func testChangingTheHomeserverDropsTheOldOptions() async {
        let model = makeModel()
        model.homeserver = "one.example"
        await model.discover()
        XCTAssertNotNil(model.options)

        model.homeserver = "two.example"
        model.homeserverDidChange()

        XCTAssertNil(model.options)
        XCTAssertFalse(model.showsPasswordLogin)
    }

    func testTheSameHomeserverKeepsItsOptions() async {
        let model = makeModel()
        model.homeserver = "one.example"
        await model.discover()

        model.homeserver = " one.example "
        model.homeserverDidChange()

        XCTAssertNotNil(model.options)
    }

    func testPasswordSignInNeedsBothFields() async {
        let recorder = Recorder()
        let model = makeModel(recorder: recorder)
        await model.discover()

        XCTAssertFalse(model.canSubmitPassword)
        model.username = "dev"
        XCTAssertFalse(model.canSubmitPassword)
        model.password = "secret"
        XCTAssertTrue(model.canSubmitPassword)

        model.username = ""
        await model.signInWithPassword()
        XCTAssertTrue(recorder.passwordSignIns.isEmpty)
    }

    func testPasswordSignInPassesTheFieldsAndClearsThePassword() async {
        let recorder = Recorder()
        let model = makeModel(recorder: recorder)
        await model.discover()
        model.username = "dev"
        model.password = "secret"

        await model.signInWithPassword()

        XCTAssertEqual(recorder.passwordSignIns.count, 1)
        XCTAssertEqual(recorder.passwordSignIns.first?.0, "dev")
        XCTAssertEqual(recorder.passwordSignIns.first?.1, "secret")
        XCTAssertEqual(model.password, "")
        XCTAssertNil(model.errorMessage)
    }

    func testPasswordSignInFailureKeepsTheFormAndShowsTheError() async {
        let model = makeModel(signInError: TestError(errorDescription: "Invalid password"))
        await model.discover()
        model.username = "dev"
        model.password = "wrong"

        await model.signInWithPassword()

        XCTAssertEqual(model.errorMessage, "Invalid password")
        XCTAssertEqual(model.password, "wrong")
        XCTAssertFalse(model.isLoading)
    }

    func testPasswordSignInDoesNothingBeforeDiscovery() async {
        let recorder = Recorder()
        let model = makeModel(recorder: recorder)
        model.username = "dev"
        model.password = "secret"

        await model.signInWithPassword()

        XCTAssertTrue(recorder.passwordSignIns.isEmpty)
    }
}
