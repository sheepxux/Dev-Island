import os

enum IslandLogger {
    static let api     = Logger(subsystem: "com.island.app", category: "api")
    static let webhook = Logger(subsystem: "com.island.app", category: "webhook")
    static let tunnel  = Logger(subsystem: "com.island.app", category: "tunnel")
    static let store   = Logger(subsystem: "com.island.app", category: "store")
    static let sync    = Logger(subsystem: "com.island.app", category: "sync")
    static let storage = Logger(subsystem: "com.island.app", category: "storage")
}
