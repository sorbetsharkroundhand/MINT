#ifndef PURLORY_CKIWI_BRIDGE_H
#define PURLORY_CKIWI_BRIDGE_H
#include <Kiwi/capi.h>
#ifdef __cplusplus
extern "C" {
#endif
const char *purlory_kiwi_bridge_version(void);
kiwi_builder_h purlory_kiwi_builder_init_fp32(const char *model_path);
#ifdef __cplusplus
}
#endif
#endif
