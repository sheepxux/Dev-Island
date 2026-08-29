#!/usr/bin/env swift

import CoreGraphics
import Foundation

private enum DisplaySessionState: String, Equatable {
    case unlocked
    case locked
    case unknown
}

private func booleanValue(_ value: Any?) -> Bool? {
    if let number = value as? NSNumber {
        return number.boolValue
    }
    return nil
}

/// `CGSSessionScreenIsLocked` is present while the login window owns the
/// display, but macOS commonly omits the key for a normal unlocked session.
/// Treat that omission as unlocked only when the same current-session
/// dictionary proves both active-console ownership and completed login.
private func classifyDisplaySession(
    _ dictionary: [String: Any]?
) -> DisplaySessionState {
    guard let dictionary else { return .unknown }

    if booleanValue(dictionary["CGSSessionScreenIsLocked"]) == true {
        return .locked
    }

    guard booleanValue(dictionary["kCGSSessionOnConsoleKey"]) == true,
          booleanValue(dictionary["kCGSessionLoginDoneKey"]) == true else {
        return .unknown
    }
    return .unlocked
}

private func runSelfTest() -> Bool {
    let fixtures: [(String, [String: Any]?, DisplaySessionState)] = [
        ("missing dictionary", nil, .unknown),
        (
            "explicitly locked",
            [
                "CGSSessionScreenIsLocked": true,
                "kCGSSessionOnConsoleKey": true,
                "kCGSessionLoginDoneKey": true,
            ],
            .locked
        ),
        (
            "explicitly unlocked active session",
            [
                "CGSSessionScreenIsLocked": false,
                "kCGSSessionOnConsoleKey": true,
                "kCGSessionLoginDoneKey": true,
            ],
            .unlocked
        ),
        (
            "normal active session omits lock key",
            [
                "kCGSSessionOnConsoleKey": true,
                "kCGSessionLoginDoneKey": true,
            ],
            .unlocked
        ),
        (
            "login not complete",
            [
                "kCGSSessionOnConsoleKey": true,
                "kCGSessionLoginDoneKey": false,
            ],
            .unknown
        ),
        (
            "not the console session",
            [
                "kCGSSessionOnConsoleKey": false,
                "kCGSessionLoginDoneKey": true,
            ],
            .unknown
        ),
    ]

    for (name, dictionary, expected) in fixtures {
        let actual = classifyDisplaySession(dictionary)
        guard actual == expected else {
            fputs(
                "display-session fixture failed: \(name): "
                    + "expected \(expected.rawValue), got \(actual.rawValue)\n",
                stderr
            )
            return false
        }
    }
    return true
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--self-test"] {
    guard runSelfTest() else { exit(1) }
    print("Display session state fixtures: PASS")
    exit(0)
}

guard arguments.isEmpty else {
    fputs("usage: display-session-state.swift [--self-test]\n", stderr)
    exit(64)
}

let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
print(classifyDisplaySession(dictionary).rawValue)
