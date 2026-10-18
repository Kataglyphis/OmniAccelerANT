#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Starts the Rust task that speaks the OmniAccelerANT USB-serial protocol. */
void omni_proto_start(void);

/* Called from the ESP-WHO detection callback on the detect task. */
void omni_proto_on_detections(unsigned count, unsigned score_permille);

#ifdef __cplusplus
}
#endif
