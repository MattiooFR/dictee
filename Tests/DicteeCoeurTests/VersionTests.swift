import Testing
@testable import DicteeCoeur

@Test("la version est exposée")
func version() { #expect(Version.courante == "0.2.0") }
