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
        let utc = AulaDate.parse("2026-03-01T08:00:00Z")
        XCTAssertEqual(AulaDate.parse("2026-03-01T09:00:00+0100"), utc)
        XCTAssertEqual(AulaDate.parse("2026-03-01 09:00:00+01:00"), utc)
        XCTAssertEqual(AulaDate.parse("2026-03-01T09:00:00"), utc)   // naive = Copenhagen time
        XCTAssertEqual(AulaDate.parse("2026-03-01 09:00:00"), utc)
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
    func testLoginAttemptsPreferMatchingState() {
        LoginAttempts.clear()
        let first = PKCE.make(), second = PKCE.make()
        LoginAttempts.add(first)
        LoginAttempts.add(second)
        XCTAssertEqual(LoginAttempts.verifiers(for: first.state), [first.verifier, second.verifier])
        XCTAssertEqual(LoginAttempts.verifiers(for: nil), [second.verifier, first.verifier])
        LoginAttempts.clear()
        XCTAssertEqual(LoginAttempts.verifiers(for: nil), [])
    }

    func testEntities() {
        XCTAssertEqual(HTML.plainText("don&#8217;t &#x2013; ok"), "don’t – ok")
        XCTAssertEqual(HTML.decodeEntities("&amp;lt;b&amp;gt; &amp; &aelig;"), "&lt;b&gt; & æ")
        XCTAssertEqual(HTML.decodeEntities("&unknown;"), "&unknown;")
        XCTAssertEqual(HTML.plainText("<p>Husk <b>madpakke</b>&nbsp;i morgen</p>"), "Husk madpakke i morgen")
    }

    func testMultiDayEvents() {
        let start = AulaDate.parse("2026-12-21T00:00:00")!
        let holiday = Event(id: "h", title: "Juleferie", start: start, end: AulaDate.parse("2026-12-24T00:00:00")!, allDay: true,
                            location: nil, teacher: nil, substitute: nil, hasSubstitute: false, type: nil, childIds: [])
        XCTAssertTrue(holiday.occurs(on: AulaDate.parse("2026-12-23T12:00:00")!))
        XCTAssertFalse(holiday.occurs(on: AulaDate.parse("2026-12-24T12:00:00")!))
    }

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

final class MoreTests: XCTestCase {
    func testDotNetDate() {
        let d = AulaAPI.parseDotNetDate("/Date(1771196400000-0000)/")
        XCTAssertEqual(d?.timeIntervalSince1970, 1771196400)
    }
}

final class ActionsTests: XCTestCase {
    func testCreatedThreadAcceptsAnyShape() throws {
        func id(_ json: String) throws -> String? {
            try JSONDecoder().decode(Envelope<CreatedThread>.self, from: Data(json.utf8)).data?.id
        }
        XCTAssertEqual(try id(#"{"data":12345}"#), "12345")
        XCTAssertEqual(try id(#"{"data":{"threadId":77}}"#), "77")
        XCTAssertEqual(try id(#"{"data":{"id":"abc"}}"#), "abc")
    }

    func testVacationAnswerDaysSkipWeekends() {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 13   // Friday
        let fri = Calendar.week.date(from: c)!
        let tue = Calendar.week.date(byAdding: .day, value: 4, to: fri)!
        let req = VacationRequest(id: 1, responseId: 2, childId: 3, childName: "Emma", title: "Jul",
                                  start: fri, end: tue, deadline: nil, note: nil, isEditable: true,
                                  isMissingAnswer: true, needsTimes: false)
        XCTAssertEqual(VacationAnswerForm.days(for: req).count, 3)  // Fri, Mon, Tue
    }

    func testThreadMarkedFlag() throws {
        let t = try JSONDecoder().decode(ThreadDTO.self, from: Data(#"{"id":1,"subject":"x","read":true,"marked":true}"#.utf8)).model
        XCTAssertEqual(t.isMarked, true)
    }
}
