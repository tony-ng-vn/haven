import ConvexMobile
import Foundation

extension EventReference {
    var convexArguments: [String: ConvexEncodable?] {
        [
            "clientKey": clientKey,
            "title": title,
            "startedAt": startedAt.timeIntervalSince1970 * 1_000,
        ]
    }

    var convexArgument: [String: ConvexEncodable?] { convexArguments }
}
