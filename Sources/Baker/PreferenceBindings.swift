import SwiftUI

extension AppStorage where Value == Bool {
    init(_ key: PreferenceKey<Bool>, store: UserDefaults? = nil) {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }
}
extension AppStorage where Value == String {
    init(_ key: PreferenceKey<String>, store: UserDefaults? = nil) {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }
}
