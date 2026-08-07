import ConvexMobile
import Foundation

extension EventReference {
    var convexArguments: [String: ConvexEncodable?] {
        var arguments: [String: ConvexEncodable?] = [
            "clientKey": clientKey,
            "title": title,
            "startedAt": startedAt.timeIntervalSince1970 * 1_000,
        ]
        if let source {
            arguments["sourceProvider"] = source.provider.rawValue
            arguments["sourceEventId"] = source.externalId
            arguments["sourceStartedAt"] = source.scheduledStartAt.timeIntervalSince1970 * 1_000
            arguments["sourceEndedAt"] = source.scheduledEndAt.timeIntervalSince1970 * 1_000
        }
        return arguments
    }

    var convexArgument: [String: ConvexEncodable?] { convexArguments }
}
