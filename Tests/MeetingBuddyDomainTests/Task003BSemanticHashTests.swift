import Testing
@testable import MeetingBuddyDomain

@Suite
struct Task003BSemanticHashTests {
    @Test
    func task003BSemanticHashesAreFrozen() throws {
        #expect(
            try Task003BFixtures.meetingProfile().calculatedSemanticContentHash().lowercaseHex
                == "3ba9223138d1da1318b232f5534ab38651ce4d02f62fa70079d515266ed678f9"
        )
        #expect(
            try Task003BFixtures.transcript().calculatedSemanticContentHash().lowercaseHex
                == "f987b333b2d38784463de18fa93363c8d6c7fc42e14c2befc9a93b1949f23588"
        )
        #expect(
            try Task003BFixtures.translation().calculatedSemanticContentHash().lowercaseHex
                == "a375af0c9ae1b7ee76e2df1765f5725e758b9a1463a9b93fff16c2805507a34d"
        )
        #expect(
            try Task003BFixtures.actor().calculatedSemanticContentHash().lowercaseHex
                == "ccc18ea95efe492a4a17fa291c57f00cfb4572aa8b110f96d96e11becd44d0a0"
        )
        #expect(
            try Task003BFixtures.capacity().calculatedSemanticContentHash().lowercaseHex
                == "8db32aa098fb5e05c80d7d73324fc55772fd04ac384cd27bf92ce788ef5543c9"
        )
        #expect(
            try Task003BFixtures.assignment().calculatedSemanticContentHash().lowercaseHex
                == "ac885750bda71e296830000b95a9613c4c2f8b167b1058b9d1a822b21e2aeb2e"
        )
    }
}
