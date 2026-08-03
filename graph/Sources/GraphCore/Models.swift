import Foundation

/// A row from the chat.db `handle` table: one sender identity on one service.
public struct RawHandle: Sendable, Equatable {
    public let rowID: Int64
    public let identifier: String
    public let service: String

    public init(rowID: Int64, identifier: String, service: String) {
        self.rowID = rowID
        self.identifier = identifier
        self.service = service
    }
}

/// A row from the chat.db `chat` table, with its member roster from `chat_handle_join`.
public struct RawChat: Sendable, Equatable {
    public let rowID: Int64
    public let guid: String
    public let style: Int
    public let chatIdentifier: String?
    public let serviceName: String?
    public let displayName: String?
    /// Roster from chat_handle_join, not from message activity: a silent member still appears here.
    public let memberHandleRowIDs: [Int64]

    public init(
        rowID: Int64,
        guid: String,
        style: Int,
        chatIdentifier: String?,
        serviceName: String?,
        displayName: String?,
        memberHandleRowIDs: [Int64]
    ) {
        self.rowID = rowID
        self.guid = guid
        self.style = style
        self.chatIdentifier = chatIdentifier
        self.serviceName = serviceName
        self.displayName = displayName
        self.memberHandleRowIDs = memberHandleRowIDs
    }
}

/// A row from the chat.db `message` table, joined to the chat it belongs to.
/// Deliberately has no field that can carry message text (constraint 3).
public struct RawMessage: Sendable, Equatable {
    public let rowID: Int64
    public let chatRowID: Int64
    public let handleRowID: Int64?
    public let isFromMe: Bool
    public let date: Date

    public init(rowID: Int64, chatRowID: Int64, handleRowID: Int64?, isFromMe: Bool, date: Date) {
        self.rowID = rowID
        self.chatRowID = chatRowID
        self.handleRowID = handleRowID
        self.isFromMe = isFromMe
        self.date = date
    }
}

/// The in-memory working model produced by extracting one chat.db.
public struct ChatExtract: Sendable, Equatable {
    public let handles: [RawHandle]
    public let chats: [RawChat]
    public let messages: [RawMessage]
    /// Messages with no chat_message_join row: skipped, not fatal, counted for measurement.
    public let unjoinedMessageCount: Int

    public init(handles: [RawHandle], chats: [RawChat], messages: [RawMessage], unjoinedMessageCount: Int) {
        self.handles = handles
        self.chats = chats
        self.messages = messages
        self.unjoinedMessageCount = unjoinedMessageCount
    }
}

/// A row from the AddressBook `ZABCDRECORD` table, with attached phones and emails.
public struct ContactRecord: Sendable, Equatable {
    /// Z_PK: db-local, still useful for ZOWNER joins inside the one db it came from, but
    /// not distinct across databases. The real store is three separate abcddb files, each
    /// with its own Z_PK space, so this alone is never safe to key a merged list on.
    public let recordID: Int64
    /// ZUNIQUEID: non-null and distinct on every ABCDContact row, and stable across resyncs
    /// unlike recordID. The safe key for anything spanning more than one contacts database.
    public let uniqueID: String
    public let firstName: String?
    public let lastName: String?
    public let organization: String?
    public let nickname: String?
    public let phoneNumbers: [String]
    public let emails: [String]
    public let thumbnailImageData: Data?

    public init(
        recordID: Int64,
        uniqueID: String,
        firstName: String?,
        lastName: String?,
        organization: String?,
        nickname: String?,
        phoneNumbers: [String],
        emails: [String],
        thumbnailImageData: Data?
    ) {
        self.recordID = recordID
        self.uniqueID = uniqueID
        self.firstName = firstName
        self.lastName = lastName
        self.organization = organization
        self.nickname = nickname
        self.phoneNumbers = phoneNumbers
        self.emails = emails
        self.thumbnailImageData = thumbnailImageData
    }
}
