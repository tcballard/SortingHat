import Foundation

public enum DecisionJSONDecoder {
    public static func decode(_ data: Data) throws -> Decision {
        if let decision = try? JSONDecoder().decode(Decision.self, from: data) { return decision }
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            throw HatError.invalidResponse(text)
        }
        let json = Data(text[start...end].utf8)
        do { return try JSONDecoder().decode(Decision.self, from: json) }
        catch { throw HatError.invalidResponse(text) }
    }
}
