import Foundation

public struct ConverterDefaults {
    public static var content: ContentConverter = JSONConverter()
    public static var query: URLFormConverter = URLFormConverter()
}

// Used for building a RawRequest.
public struct PartialRequest {
    public enum BodyContent {
        case fields([String: AnyEncodable])
        case value(AnyEncodable)
    }
    
    // Data
    public var method: String
    public var path: String
    public var parameters: [String: String]
    public var headers: [String: String]
    public var query: [String: AnyEncodable]
    public var body: BodyContent?
    
    // Converters
    public var preferredContentConverter: ContentConverter?
    private var _contentConverter: ContentConverter { preferredContentConverter ?? ConverterDefaults.content }
    public var contentConverter: ContentConverter { preferredKeyMapping.map { _contentConverter.with(keyMapping: $0) } ?? _contentConverter }
    
    public var preferredQueryConverter: URLFormConverter?
    private var _queryConverter: URLFormConverter { preferredQueryConverter ?? ConverterDefaults.query }
    public var queryConverter: URLFormConverter { preferredKeyMapping.map { _queryConverter.with(keyMapping: $0) } ?? _queryConverter }
    
    public var preferredKeyMapping: KeyMapping?
    
    init() {
        self.method = "GET"
        self.path = "/"
        self.body = nil
        self.query = [:]
        self.headers = [:]
        self.parameters = [:]
        self.preferredContentConverter = nil
        self.preferredQueryConverter = nil
        self.preferredKeyMapping = nil
    }
    
    // MARK: Building
    
    public mutating func setBody<E: Encodable>(_ value: E) {
        if let body = body {
            preconditionFailure("Tried to set an endpoint body to type \(E.self), but it already had one: \(body).")
        }
        
        body = .value(AnyEncodable(value))
    }
    
    public mutating func addQuery<E: Encodable>(_ key: String, value: E) {
        query[key] = AnyEncodable(value)
    }
    
    public mutating func addField<E: Encodable>(_ key: String, value: E) {
        var fields: [String: AnyEncodable] = [:]
        if let body = body {
            guard case .fields(let existingFields) = body else {
                preconditionFailure("Tried to add a field, \(key): \(E.self), to an endpoint, but it already had a body, \(body). @Body and @Field are mutually exclusive.")
            }
            
            fields = existingFields
        }
        
        fields[key] = AnyEncodable(value)
        body = .fields(fields)
    }
    
    // MARK: Create
    
    public func create(baseURL: String) throws -> RawRequest {
        let mappedParameters = Dictionary(uniqueKeysWithValues: parameters.map { (preferredKeyMapping?.mapTo(input: $0) ?? $0, $1) })
        let body = try bodyData()
        var headers = headers
        headers["Content-Type"] = contentConverter.contentType
        headers["Content-Length"] = "\(body?.count ?? 0)"
        return RawRequest(method: method, baseURL: baseURL, path: try replacedPath(mappedParameters), headers: headers, parameters: mappedParameters, query: try queryString(), body: body, queryConverter: queryConverter, contentConverter: contentConverter)
    }
    
    private func bodyData() throws -> Data? {
        guard let body = body else { return nil }
        switch body {
        case .value(let value):
            return try contentConverter.encode(value)
        case .fields(let fields):
            if contentConverter is JSONConverter, let mapping = preferredKeyMapping {
                // For some reason, JSONEncoder doesn't map dict keys with the
                // preferred keymapping when encoding. We'll need to manually
                // do it.
                let mappedFields = Dictionary(uniqueKeysWithValues: fields.map { (mapping.mapTo(input: $0), $1) })
                return try contentConverter.encode(mappedFields)
            } else {
                return try contentConverter.encode(fields)
            }
        }
    }
    
    private func replacedPath(_ mappedParameters: [String: String]) throws -> String {
        try mappedParameters.reduce(into: path) { newPath, component in
            guard newPath.contains(":\(component.key)") else {
                throw PapyrusError("Tried to set path component `\(component.key)` but did not find `:\(component.key)` in \(path).")
            }
            
            newPath = newPath.replacingOccurrences(of: ":\(component.key)", with: component.value)
        }
    }
    
    private func queryString() throws -> String {
        guard !query.isEmpty else { return "" }
        let queryString: String = try queryConverter.encode(query)
        guard let percentEncoded = queryString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return "" }
        return percentEncoded
    }
}
