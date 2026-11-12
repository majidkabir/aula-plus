import XCTest
@testable import AulaPlus

final class DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(Envelope<T>.self, from: Data(json.utf8)).data!
    }

    func testPKCEChallengeIsBase64URLSHA256() {
        // Expected value: python3 -c "import hashlib,base64; base64.urlsafe_b64encode(hashlib.sha256(b'...').digest())"
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K_uhtvbFJbYZwY8zfFk1Dc4cSU"),
                       "_DlCEJejw0P-_ZkBafI2EDiATci3OhR2jjENo-0iYaA")
    }

    func testAuthorizeURLHasPKCEParameters() {
        let p = PKCE.make()
        let items = URLComponents(url: p.authorizeURL, resolvingAgainstBaseURL: false)!.queryItems!
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["code_challenge_method"], "S256")
        XCTAssertEqual(dict["redirect_uri"], "https://app-private.aula.dk")
        XCTAssertEqual(dict["state"], p.state)
    }

    func testDates() {
        XCTAssertNotNil(AulaDate.parse("2026-03-01T09:00:00Z"))
        XCTAssertNotNil(AulaDate.parse("2026-03-01T09:00:00+01:00"))
        XCTAssertNotNil(AulaDate.parse("2026-03-01T09:00:00.123+01:00"))
        XCTAssertNotNil(AulaDate.parse("2026-03-01T09:00:00"))
        XCTAssertNil(AulaDate.parse(""))
        XCTAssertEqual(AulaDate.shortTime("07:45:00"), "07:45")
        XCTAssertEqual(AulaDate.shortTime("2026-11-12T15:30:00"), "15:30")
    }

    func testProfileWithLooseTypes() throws {
        let json = """
        {"status":{"code":0},"data":{"profiles":[{"displayName":"Majid G","institutionProfiles":[{"id":11}],
        "children":[{"id":"101","profileId":5,"name":"Emma G","userId":"emma123",
          "institutionProfile":{"institutionName":"Skolen","institutionCode":"280001"},
          "profilePicture":{"url":"https://x/y.png"}}, "junk"]}]}}
        """
        let p = try decode(ProfilesByLoginDTO.self, json).profiles!.items[0]
        let c = p.children!.items[0].toChild()
        XCTAssertEqual(c.id, 101)
        XCTAssertEqual(c.firstName, "Emma")
        XCTAssertEqual(c.institutionCode, "280001")
        XCTAssertEqual(p.children!.items.count, 1)
    }

    func testThreadAndMessages() throws {
        let threads = try decode(ThreadsDTO.self, """
        {"data":{"threads":[{"id":123,"subject":"Tur","read":false,
          "latestMessage":{"sendDateTime":"2026-11-10T08:00:00+01:00","sender":{"fullName":"Lærer L"},
          "text":{"html":"<p>Husk <b>madpakke</b>&nbsp;i morgen</p>"}}}]}}
        """).threads!.items.map(\.model)
        XCTAssertEqual(threads[0].id, "123")
        XCTAssertFalse(threads[0].isRead)
        XCTAssertEqual(threads[0].preview, "Husk madpakke i morgen")
        XCTAssertEqual(threads[0].sender, "Lærer L")

        let page = try decode(ThreadMessagesDTO.self, """
        {"data":{"subject":"Tur","moreMessagesExist":false,"mailBoxOwner":{"mailBoxOwnerType":"institutionProfile"},
          "messages":[{"id":"m2","messageType":"Message","text":"plain body","sender":{"fullName":"A"}},
                      {"id":"e1","messageType":"RecipientAdded"},
                      {"id":"m1","messageType":"MessageEdited","text":{"html":"<i>x</i>"},
                       "attachments":[{"name":"plan.pdf","file":{"url":"https://f/plan.pdf"}}]}]}}
        """).model
        XCTAssertEqual(page.messages.map(\.id), ["m2", "m1"])
        XCTAssertEqual(page.messages[0].html, "plain body")
        XCTAssertEqual(page.messages[1].attachments.first?.url?.absoluteString, "https://f/plan.pdf")
        XCTAssertTrue(page.isOwnMailbox)
    }

    func testEventSubstitute() throws {
        let list = try decode(Lossy<EventDTO>.self, """
        {"data":[{"id":1,"title":"Matematik","startDateTime":"2026-11-12T08:00:00+01:00",
          "endDateTime":"2026-11-12T08:45:00+01:00","belongsToProfiles":[101],
          "primaryResource":{"name":"Lokale 3"},
          "lesson":{"lessonStatus":"Substitute","participants":[
            {"participantRole":"primaryTeacher","teacherName":"Hansen"},
            {"participantRole":"substituteTeacher","teacherName":"Jensen"}]}},
          {"id":2,"title":"no date"}]}
        """)
        let events = list.items.compactMap(\.model)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].hasSubstitute)
        XCTAssertEqual(events[0].substitute, "Jensen")
        XCTAssertEqual(events[0].childIds, [101])
    }

    func testWeekKeys() {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 12
        let d = Calendar.week.date(from: c)!
        XCTAssertEqual(Week.key(d), "2026-W46")
        XCTAssertEqual(Calendar.week.component(.weekday, from: Week.start(of: d)), 2) // Monday
    }
}

final class MessagingTests: XCTestCase {
    func testReplyHTMLEscapesAndKeepsParagraphs() {
        XCTAssertEqual(AulaAPI.htmlFromPlainText("Hej <3\nfra os\n\nTak & hilsen"),
                       "<p>Hej &lt;3<br>fra os</p><p>Tak &amp; hilsen</p>")
    }

    func testLinkAttachmentIsMarked() throws {
        let a = try JSONDecoder().decode(AttachmentDTO.self, from: Data(#"{"link":{"name":"Site","url":"https://x.dk"}}"#.utf8)).model
        XCTAssertEqual(a.isLink, true)
        XCTAssertEqual(a.name, "Site")
    }
}
