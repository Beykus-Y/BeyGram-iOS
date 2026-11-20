#ifndef BEYGRAM_MIHOMO_CORE_H
#define BEYGRAM_MIHOMO_CORE_H

/*
 * C entry points of the Mihomo core archive (see ../../core/cmd/beygram-mihomo).
 * A request and a reply are UTF-8 JSON. Free every reply with BGMihomoFree.
 */

#ifdef __cplusplus
extern "C" {
#endif

/* Handles one request {"id", "method", "data"} and returns one reply {"id", "code", "data" | "message"}. */
char *BGMihomoInvoke(const char *request);

/* Frees a reply returned by BGMihomoInvoke. */
void BGMihomoFree(char *reply);

#ifdef __cplusplus
}
#endif

#endif /* BEYGRAM_MIHOMO_CORE_H */
