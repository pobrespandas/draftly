import SwiftUI

struct WindowModelKey: FocusedValueKey { typealias Value = WindowModel }
extension FocusedValues {
    var windowModel: WindowModel? { get { self[WindowModelKey.self] } set { self[WindowModelKey.self] = newValue } }
}
