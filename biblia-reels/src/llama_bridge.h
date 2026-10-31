#pragma once

/* Inference glue for llama.cpp v0.8.0. The GGUF is downloaded by the app; it is not linked in. */

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct br_engine br_engine;
typedef void (*br_progress_fn)(float progress, void *user);
typedef void (*br_text_fn)(const char *full_text, void *user);

br_engine *br_engine_load(const char *path, int n_ctx, int n_threads,
                          br_progress_fn on_load, void *user,
                          char *err, int errlen);
void br_engine_free(br_engine *engine);

/* roles/contents are earlier turns only. system and user_text are added around them.
   Returns a malloc'd UTF-8 string the caller frees, or NULL on failure. */
char *br_engine_chat(br_engine *engine,
                     const char *system_text,
                     const char **roles, const char **contents, int n_history,
                     const char *user_text,
                     int max_tokens,
                     br_text_fn on_partial, void *user,
                     char *err, int errlen);

#ifdef __cplusplus
}
#endif
