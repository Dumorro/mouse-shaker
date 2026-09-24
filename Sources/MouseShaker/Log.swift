import OSLog

/// `log stream --predicate 'subsystem == "dev.dumorro.mouseshaker"' --level info`
enum Log {
    static let subsystem = "dev.dumorro.mouseshaker"
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let system = Logger(subsystem: subsystem, category: "system")
}
