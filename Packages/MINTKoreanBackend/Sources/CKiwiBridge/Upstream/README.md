# Pinned Kiwi constructor headers

These unmodified public headers come from Kiwi 0.24.0, revision
`6e16bbcfc0940fabccbdde574abb4ea3a659588e`, matching the native archive and
model index. `provenance.json` records each file's SHA-256. `LICENSE` is the
upstream Apache-2.0 license; the existing distribution notices also cover Kiwi.

Only the transitive public includes of `kiwi/Kiwi.h` are retained. They are
private build inputs to `builder.cpp`, not part of the exported Swift module.
No upstream engine source is compiled and the pinned archive is unchanged.

The upstream XCFramework build uses `KIWI_USE_MIMALLOC=ON` and C++17. Both
package manifests use those same settings for this adapter so the public C++
types have matching allocator definitions. `mimalloc.h` and `MIMALLOC-LICENSE`
come from Kiwi's pinned mimalloc submodule; no allocator source is recompiled.

The 0.24.0 C API exposes quantized CoNg but does not expose `congFp32`.
The published scalar archive cannot execute quantized CoNg and prints one
fallback warning for `cong.mdl` and another for `nounchr.mdl`. The adapter
selects `kiwi::ModelType::congFp32` through its public C++ constructor, then
hands ownership to the existing C API. This selects the FP32 implementation
already used after fallback; it neither suppresses stderr nor disables the
diagnostics provider. Builder construction remains on the native worker thread.

Update the headers, archive and model provenance together when upgrading Kiwi.
The adapter rejects a runtime version other than 0.24.0.
