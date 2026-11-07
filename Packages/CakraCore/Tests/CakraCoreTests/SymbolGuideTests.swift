import CakraCore
import XCTest

final class SymbolGuideTests: XCTestCase {
    func testSpecFollowsMapScale() {
        XCTAssertEqual(SymbolGuide.Spec.for(scaleDenominator: 4000), .issprom)
        XCTAssertEqual(SymbolGuide.Spec.for(scaleDenominator: 5000), .issprom)
        XCTAssertEqual(SymbolGuide.Spec.for(scaleDenominator: 10000), .isom)
        XCTAssertEqual(SymbolGuide.Spec.isom.url.absoluteString, "https://omapwiki.orienteering.sport/specifications/isom/")
        XCTAssertEqual(SymbolGuide.Spec.issprom.url.absoluteString, "https://omapwiki.orienteering.sport/specifications/issprom/")
    }

    func testSearchTerms() {
        XCTAssertEqual(SymbolGuide.searchTerms(for: "101.0"), ["101.0", "101"])
        XCTAssertEqual(SymbolGuide.searchTerms(for: "509.1"), ["509.1"])
        XCTAssertEqual(SymbolGuide.searchTerms(for: " "), [])
        XCTAssertEqual(SymbolGuide.searchTerms(for: "512.100"), ["512.100", "512.1"])
        XCTAssertEqual(SymbolGuide.searchTerms(for: "501.30"), ["501.30", "501.3"])
    }
}
