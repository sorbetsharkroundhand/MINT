import Foundation
import MLXLMCommon

/// 연속 예측 사이 프리필 KV를 재사용하는 프롬프트 캐시 (PLAN §12 — 지연의 핵심).
///
/// 타이핑은 대부분 "직전 프롬프트 뒤에 몇 글자"라, 직전 프롬프트와의 최장 공통
/// 접두(LCP)만 캐시에 남기고(trim) 새 토큰만 증분 프리필한다. 생성이 캐시에
/// 덧붙인 토큰 수는 따로 추적하지 않는다 — trim 양을 `offset − lcp`로 잡으면
/// 생성 토큰이든 중간에 취소된 프리필이든 offset(캐시의 진실)이 알아서 정리한다.
/// "min(offset, 기록된 프롬프트 길이)까지는 기록과 일치"가 항상 성립하는 이유는
/// 프리필이 토큰 순서대로 진행되기 때문이다.
///
/// 동시성: `KVCache`는 Sendable이 아니라 이 박스가 @unchecked로 감싸고 모든
/// 접근을 NSLock으로 직렬화한다. 엔진 actor의 재진입(예: 폴더 명명과 예측이
/// 겹침)으로 생성이 겹치는 드문 경우엔 busy 가드가 재사용을 포기한다 —
/// 겹친 쪽은 캐시 없이 생성한다. 틀린 캐시보다 느린 프리필이 낫다.
/// LCP 재사용 판정의 순수 로직 — KV 캐시·모델 없이 결정적으로 검증 가능한 부분
/// (PLAN §12). 박스(`PromptCacheBox`)는 실제 trim·캐시 수명만 담당하고,
/// "얼마나 재사용하고 얼마나 잘라내는가"의 계산은 여기서 한다.
enum PromptCacheMath {

    /// 캐시 상태에서 새 프롬프트로 재사용 가능한 접두 토큰 수.
    ///
    /// - `offset`: 캐시에 실제로 들어있는 토큰 수 (생성·중단된 프리필 포함 — 진실).
    /// - `recorded`: 마지막 `commit`이 기록한 프롬프트 토큰.
    ///   `min(offset, recorded.count)`까지는 기록과 일치가 항상 성립한다 —
    ///   프리필이 토큰 순서대로 진행하기 때문. 생성 토큰은 기록 밖이라 재사용에 안 센다.
    /// - 요청이 통째로 접두와 같으면 최소 1토큰을 남긴다 — 빈 입력으론 생성을
    ///   시작할 수 없다 (뒤로 지우기 직후).
    static func reusablePrefix(offset: Int, recorded: [Int], requested: [Int]) -> Int {
        let known = min(offset, recorded.count)
        var lcp = 0
        while lcp < known, lcp < requested.count, recorded[lcp] == requested[lcp] {
            lcp += 1
        }
        if lcp == requested.count { lcp -= 1 }
        return max(lcp, 0)
    }

    /// 재사용분을 뺀 trim 양 — 생성 토큰이든 중단된 프리필이든 이 값으로 몰아 정리된다.
    static func trimAmount(offset: Int, reused: Int) -> Int { offset - reused }
}

final class PromptCacheBox: @unchecked Sendable {

    struct Reuse {
        let cache: [KVCache]
        /// 이번에 프리필할 토큰 — 전체 프롬프트에서 재사용분을 뺀 서픽스.
        let suffix: [Int]
        /// 프리필을 건너뛴(재사용된) 앞부분 토큰 수 — 벤치·상태 표시용.
        let reusedTokens: Int
    }

    private let lock = NSLock()
    private var cache: [KVCache]?
    /// 캐시 앞부분과 일치한다고 보장되는 프롬프트 토큰 기록.
    private var promptTokens: [Int] = []
    private var modelID: String?
    private var busy = false

    /// 재사용 준비. busy(생성 겹침)거나 토큰이 비면 nil — 호출부는 캐시 없이
    /// 생성한다. 성공하면 반드시 `commit` 또는 `abandon`으로 짝을 맞춘다.
    func begin(
        modelID: String,
        tokens: [Int],
        model: any LanguageModel,
        parameters: GenerateParameters
    ) -> Reuse? {
        lock.lock()
        defer { lock.unlock() }
        guard !busy, !tokens.isEmpty else { return nil }
        busy = true

        if self.modelID == modelID,
            let cache,
            !promptTokens.isEmpty,
            let reuse = reusableSuffix(cache: cache, tokens: tokens)
        {
            return reuse
        }
        // 재사용 불가 — 새 캐시로 전체 프리필 (다음 요청부터 재사용된다).
        let fresh = makePromptCache(model: model, parameters: parameters)
        cache = fresh
        promptTokens = []
        self.modelID = modelID
        return Reuse(cache: fresh, suffix: tokens, reusedTokens: 0)
    }

    /// LCP 이후를 trim해 서픽스만 남긴다. 자를 수 없는 캐시(회전형 등)나
    /// LCP 0이면 nil → 호출부(begin)가 새 캐시로 간다.
    private func reusableSuffix(cache: [KVCache], tokens: [Int]) -> Reuse? {
        let offset = cache.first?.offset ?? 0
        let lcp = PromptCacheMath.reusablePrefix(
            offset: offset, recorded: promptTokens, requested: tokens)
        guard lcp > 0, canTrimPromptCache(cache) else { return nil }
        let trim = PromptCacheMath.trimAmount(offset: offset, reused: lcp)
        guard trimPromptCache(cache, numTokens: trim) == trim else { return nil }
        return Reuse(cache: cache, suffix: Array(tokens[lcp...]), reusedTokens: lcp)
    }

    /// 생성 종료(문장 경계 조기 종료·협조 취소 포함) — 프리필된 프롬프트를 기록.
    func commit(tokens: [Int]) {
        lock.lock()
        defer { lock.unlock() }
        promptTokens = tokens
        busy = false
    }

    /// 생성이 던졌다 — 캐시 상태를 신뢰할 수 없으니 통째로 버린다.
    func abandon() {
        lock.lock()
        defer { lock.unlock() }
        cache = nil
        promptTokens = []
        busy = false
    }

    /// 모델 교체·메모리 압박 — 전부 폐기.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cache = nil
        promptTokens = []
        modelID = nil
        busy = false
    }
}
