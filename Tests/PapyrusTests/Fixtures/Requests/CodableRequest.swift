import Papyrus

struct CodableRequest: TestableRequest {
    static var expected = CodableRequest(string: "foo", int: 0, bool: false, double: 0.123456)
    
    static func input(contentConverter: ContentConverter) throws -> RawTestRequest {
        let body = try contentConverter.encode(expected)
        return RawTestRequest(
            headers: [
                "Content-Type": contentConverter.contentType,
                "Content-Length": String(body.count)
            ],
            body: body
        )
    }
    
    var string: String
    var int: Int
    var bool: Bool
    var double: Double
}
