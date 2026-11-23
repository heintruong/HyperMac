import Testing
@testable import HyperMac

struct UpdateSignatureTests {
    @Test func rejectsAppsNotSignedWithOwnCertificate() {
        #expect(!UpdateManager.isSignedLikeSelf("/nonexistent/HyperMac.app"))
        #expect(!UpdateManager.isSignedLikeSelf("/System/Applications/Calculator.app")) // Apple-signed, different signer
    }
}
