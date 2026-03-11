import Foundation
import SwiftUI

enum ExtempBindingFactory {
    static func optionalIntText(
        getValue: @escaping () -> Int?,
        setValue: @escaping (Int?) -> Void,
        fallbackText: @escaping () -> String = { "" },
        setFallbackText: @escaping (String) -> Void = { _ in },
        sanitize: @escaping (String) -> String = { $0.filter(\.isNumber) }
    ) -> Binding<String> {
        Binding(
            get: {
                if let value = getValue() {
                    return String(value)
                }
                return fallbackText()
            },
            set: { newText in
                let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    setValue(nil)
                } else {
                    setValue(Int(sanitize(trimmed)))
                }
                setFallbackText(newText)
            }
        )
    }

    static func optionalRoundedIntText(
        getValue: @escaping () -> Int?,
        setValue: @escaping (Int?) -> Void,
        parseDouble: @escaping (String) -> Double?,
        fallbackText: @escaping () -> String = { "" },
        setFallbackText: @escaping (String) -> Void = { _ in }
    ) -> Binding<String> {
        Binding(
            get: {
                if let value = getValue() {
                    return String(value)
                }
                return fallbackText()
            },
            set: { newText in
                let mapped = parseDouble(newText).map { Int($0.rounded()) }
                setValue(mapped)
                setFallbackText(newText)
            }
        )
    }

    static func mirroredString(
        getValue: @escaping () -> String,
        setValue: @escaping (String) -> Void,
        setMirror: @escaping (String) -> Void = { _ in }
    ) -> Binding<String> {
        Binding(
            get: getValue,
            set: { newValue in
                setValue(newValue)
                setMirror(newValue)
            }
        )
    }

    static func optionalDoubleText(
        getValue: @escaping () -> Double?,
        setValue: @escaping (Double?) -> Void,
        formatValue: @escaping (Double) -> String,
        parseValue: @escaping (String) -> Double?,
        fallbackText: @escaping () -> String = { "" },
        setFallbackText: @escaping (String) -> Void = { _ in }
    ) -> Binding<String> {
        Binding(
            get: {
                if let value = getValue() {
                    return formatValue(value)
                }
                return fallbackText()
            },
            set: { newText in
                let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                setValue(parseValue(trimmed))
                setFallbackText(newText)
            }
        )
    }

    static func unitIdBinding(
        units: @escaping () -> [ExtempUnit],
        getCode: @escaping () -> UnitCode?,
        setCode: @escaping (UnitCode?) -> Void,
        fallbackId: @escaping () -> Int?,
        setFallbackId: @escaping (Int?) -> Void
    ) -> Binding<Int?> {
        Binding(
            get: {
                guard let code = getCode()?.rawValue else { return fallbackId() }
                let key = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if key.isEmpty { return fallbackId() }
                return units().first(where: {
                    $0.lat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
                    || $0.code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
                })?.id
            },
            set: { newId in
                let newCode: UnitCode? = {
                    guard let newId else { return nil }
                    guard let unit = units().first(where: { $0.id == newId }) else { return nil }
                    let lat = unit.lat.trimmingCharacters(in: .whitespacesAndNewlines)
                    let code = unit.code.trimmingCharacters(in: .whitespacesAndNewlines)
                    let preferred = lat.isEmpty ? code : lat
                    if preferred.isEmpty { return nil }
                    return UnitCode(rawValue: preferred)
                }()
                setCode(newCode)
                setFallbackId(newId)
            }
        )
    }
}
