import Testing
@testable import SharedKit

@Suite struct SharedConstantsTests {
    @Test func sharedConstantsAreConsistent() {
        #expect(SharedConstants.appGroupIdentifier == "group.com.appdrop.shared")
        #expect(SharedConstants.candidateAppGroupIdentifiers == [SharedConstants.appGroupIdentifier])
        #expect(SharedConstants.supportedCountryCodes == ["us", "hk", "jp", "cn"])
        #expect(SharedConstants.isSupportedCountry("US"))
        #expect(!SharedConstants.isSupportedCountry("de"))
        #expect(SharedConstants.helperBundleIdentifier == "com.appdrop.helper")
        #expect(SharedConstants.wishdropFormatVersion == 1)
    }
}

