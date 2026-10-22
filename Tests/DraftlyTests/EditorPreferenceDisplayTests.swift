import Testing
@testable import Draftly

@Suite("Editor preference point labels")
struct EditorPreferenceDisplayTests {
    @Test(arguments: [
        (0.0, "0 pt"),
        (6.0, "6 pt"),
        (17.0, "17 pt"),
        (17.9, "17 pt"),
        (-3.9, "-3 pt"),
        (80.0, "80 pt"),
        (Double(Int.min), "-9223372036854775808 pt"),
        (Double(Int.max).nextDown, "9223372036854774784 pt")
    ])
    func finiteRepresentableValuesKeepWholePointLabels(value: Double, expected: String) {
        #expect(EditorPreferenceDisplay.wholePointLabel(value) == expected)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude,
                      -.greatestFiniteMagnitude, Double(Int.max), Double(Int.min).nextDown])
    func invalidValuesHaveAnExplicitLabelWithoutIntegerConversionTraps(_ value: Double) {
        #expect(EditorPreferenceDisplay.wholePointLabel(value) == "Invalid value")
    }
}
