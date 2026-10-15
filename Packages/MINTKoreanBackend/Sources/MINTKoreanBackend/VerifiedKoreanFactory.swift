import Foundation

struct VerifiedKoreanFactory: KoreanNativeFactory {
    func open(resources: URL, admission: @Sendable () -> Bool) throws -> any KoreanNativeHandle {
        try KiwiNativeHandle(model: KoreanResources.validate(resources, admission: admission), admission: admission)
    }
}
