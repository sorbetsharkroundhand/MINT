import Foundation
import MLXLMCommon

/// 양자화 모델의 형식 흔들림을 받는 폴백 파서. 네이티브 `.toolCall`이 우선이며,
/// 이 파서는 `<tool_call>{...}</tool_call>`·`TOOL: name {...}`·맨몸 JSON만 복구한다.
/// 파싱 뒤 Registry가 이름·필수 인자·형식을 엄격 검증한다.
public enum AgentToolCallParser {
    public struct Parsed: Sendable, Equatable {
        public var calls: [AgentToolCall]
        public var remainingText: String

        public init(calls: [AgentToolCall], remainingText: String) {
            self.calls = calls
            self.remainingText = remainingText
        }
    }

    public static func parse(_ raw: String) -> Parsed {
        var calls: [AgentToolCall] = []
        var remaining = raw

        // Hermes 태그. 닫는 태그가 빠졌어도 문자열 끝까지 한 번 복구한다.
        while let start = remaining.range(of: "<tool_call>") {
            let payloadStart = start.upperBound
            let end = remaining.range(of: "</tool_call>", range: payloadStart..<remaining.endIndex)
            let payloadEnd = end?.lowerBound ?? remaining.endIndex
            if let call = decode(String(remaining[payloadStart..<payloadEnd])) {
                calls.append(call)
            }
            let removalEnd = end?.upperBound ?? remaining.endIndex
            remaining.removeSubrange(start.lowerBound..<removalEnd)
        }

        // 단순 줄 폴백: TOOL: get_outline {} / TOOL: name {"x":1}
        var keptLines: [Substring] = []
        for line in remaining.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.uppercased().hasPrefix("TOOL:") else {
                keptLines.append(line)
                continue
            }
            let content = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let name = content.prefix { !$0.isWhitespace && $0 != "{" }
            let jsonStart = content.firstIndex(of: "{")
            let arguments: [String: JSONValue]
            if let jsonStart,
                let value = decodeJSON(String(content[jsonStart...])),
                case .object(let object) = value
            {
                arguments = object
            } else {
                arguments = [:]
            }
            if !name.isEmpty {
                calls.append(AgentToolCall(name: String(name), arguments: arguments))
            } else {
                keptLines.append(line)
            }
        }
        remaining = keptLines.joined(separator: "\n")

        // 모델이 wrapper 없이 {"name":...,"arguments":...} 하나만 낸 경우.
        if calls.isEmpty, let call = decode(remaining),
            remaining.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
        {
            calls.append(call)
            remaining = ""
        }

        return Parsed(
            calls: calls,
            remainingText: remaining.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func tagged(_ call: AgentToolCall) -> String {
        let payload: JSONValue = .object([
            "name": .string(call.name),
            "arguments": .object(call.arguments),
        ])
        return "<tool_call>\(AgentJSON.encode(payload))</tool_call>"
    }

    private static func decode(_ raw: String) -> AgentToolCall? {
        guard let value = decodeJSON(raw), case .object(let object) = value,
            let name = object["name"]?.agentString, !name.isEmpty
        else { return nil }
        let arguments: [String: JSONValue]
        if case .object(let object)? = object["arguments"] {
            arguments = object
        } else if case .string(let string)? = object["arguments"],
            let decoded = decodeJSON(string), case .object(let object) = decoded
        {
            arguments = object
        } else {
            arguments = [:]
        }
        return AgentToolCall(name: name, arguments: arguments)
    }

    /// 복구는 구조 문자 누락·코드펜스·trailing comma까지만. 필드 의미를 추측해
    /// 고치는 순간 잘못된 도구 실행이 가능해지므로 그 이상은 repair 턴에 맡긴다.
    private static func decodeJSON(_ raw: String) -> JSONValue? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("```"), let firstNewline = candidate.firstIndex(of: "\n") {
            candidate = String(candidate[candidate.index(after: firstNewline)...])
            if let fence = candidate.range(of: "```", options: .backwards) {
                candidate.removeSubrange(fence.lowerBound...)
            }
        }
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = candidate.replacingOccurrences(
            of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
        let opens = candidate.filter { $0 == "{" }.count
        let closes = candidate.filter { $0 == "}" }.count
        if opens > closes { candidate += String(repeating: "}", count: opens - closes) }
        guard let data = candidate.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
