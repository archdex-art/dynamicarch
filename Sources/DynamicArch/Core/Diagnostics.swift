import Foundation
import os

/// Structured logging for the parts of the app that interact with the system in
/// ways we cannot step through in a debugger: drag sessions, the media bridge,
/// display topology. Off by default in the unified log's "info" tier, so it
/// costs nothing until someone goes looking with:
///
///     log stream --predicate 'subsystem == "app.dynamicarch"'
enum Diagnostics {
    static let drag = Logger(subsystem: "app.dynamicarch", category: "drag")
    static let media = Logger(subsystem: "app.dynamicarch", category: "media")
    static let display = Logger(subsystem: "app.dynamicarch", category: "display")
    static let hud = Logger(subsystem: "app.dynamicarch", category: "hud")
    static let shelf = Logger(subsystem: "app.dynamicarch", category: "shelf")
}
