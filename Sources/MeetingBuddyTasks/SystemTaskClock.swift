import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct SystemTaskClock: TaskClock, Sendable {
    public init() {}

    public func now() -> UTCInstant {
        let milliseconds = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        return try! UTCInstant(millisecondsSinceUnixEpoch: max(milliseconds, 0))
    }
}
