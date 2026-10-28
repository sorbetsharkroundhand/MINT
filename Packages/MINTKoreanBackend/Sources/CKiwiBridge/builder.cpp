#include "CKiwiBridge.h"
#include <cmath>
#include <cstring>
#include "Upstream/kiwi/Kiwi.h"

// The pinned universal archive falls back to scalar FP32 for both CoNg models.
// Select that same implementation directly: the 0.24.0 C ABI exposes only the
// quantized CoNg selector, while the public C++ API also exposes congFp32.
// Keep C++ types private and return the same builder handle owned by the C ABI.
extern "C" kiwi_builder_h mint_kiwi_builder_init_fp32(const char *model_path) {
    if (!model_path || std::strcmp(kiwi_version(), "0.24.0") != 0) return nullptr;
    try {
        auto *builder = new kiwi::KiwiBuilder{
            std::string{model_path}, 1, kiwi::BuildOption::default_,
            kiwi::ModelType::congFp32, kiwi::Dialect::standard
        };
        return reinterpret_cast<kiwi_builder_h>(builder);
    } catch (...) {
        // Swift maps an unavailable builder to the existing optional diagnostics
        // failure state. Never propagate a C++ exception through the C boundary.
        return nullptr;
    }
}
