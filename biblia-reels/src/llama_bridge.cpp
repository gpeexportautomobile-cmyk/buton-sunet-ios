#include "llama_bridge.h"

#include "llama.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <stdint.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

struct br_engine {
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
    const llama_vocab *vocab = nullptr;
    int n_ctx = 2048;
    int n_threads = 4;
    std::chrono::steady_clock::time_point deadline;
};

static void set_err(char *err, int errlen, const char *msg) {
    if (!err || errlen <= 0) return;
    std::snprintf(err, (size_t)errlen, "%s", msg);
}

static bool model_progress(float progress, void *user) {
    auto *pack = (std::pair<br_progress_fn, void *> *)user;
    if (pack && pack->first) pack->first(progress, pack->second);
    return true;
}

static bool should_abort(void *user) {
    auto *engine = (br_engine *)user;
    return std::chrono::steady_clock::now() > engine->deadline;
}

static std::string token_piece(const llama_vocab *vocab, llama_token id) {
    int n = llama_token_to_piece(vocab, id, nullptr, 0, 0, true);
    if (n == 0) return "";
    std::string buf((size_t)std::abs(n), '\0');
    int wrote = llama_token_to_piece(vocab, id, buf.data(), (int32_t)buf.size(), 0, true);
    if (wrote < 0) return "";
    buf.resize((size_t)wrote);
    return buf;
}

static bool utf8_ok(const std::string &s) {
    const auto *p = (const unsigned char *)s.data();
    size_t i = 0;
    while (i < s.size()) {
        if (p[i] < 0x80) { i++; continue; }
        size_t need = 0;
        if ((p[i] & 0xE0) == 0xC0) need = 2;
        else if ((p[i] & 0xF0) == 0xE0) need = 3;
        else if ((p[i] & 0xF8) == 0xF0) need = 4;
        else return false;
        if (i + need > s.size()) return false;
        for (size_t k = 1; k < need; k++) if ((p[i + k] & 0xC0) != 0x80) return false;
        i += need;
    }
    return true;
}

static std::string valid_prefix(const std::string &s) {
    if (utf8_ok(s)) return s;
    for (size_t n = s.size(); n > 0; n--) {
        std::string cut = s.substr(0, n);
        if (utf8_ok(cut)) return cut;
    }
    return "";
}

static void batch_tokens(llama_batch_ext *batch, const llama_token *tokens, int32_t n, llama_pos pos0, bool logits) {
    llama_batch_ext_clear(batch);
    for (int32_t i = 0; i < n; i++) {
        int32_t idx = llama_batch_ext_add_token(batch, 0, tokens[i]);
        if (idx < 0) return;
        llama_pos pos = pos0 + i;
        llama_batch_ext_set_pos(batch, idx, &pos);
    }
    if (logits && n > 0) llama_batch_ext_set_output_logits(batch, n - 1, true);
}

static std::string manual_chat(const std::vector<std::pair<std::string, std::string>> &msgs) {
    std::string out;
    for (const auto &msg : msgs) {
        out += "<|im_start|>";
        out += msg.first;
        out += "\n";
        out += msg.second;
        out += "<|im_end|>\n";
    }
    out += "<|im_start|>assistant\n";
    return out;
}

static std::string apply_template(br_engine *engine, const std::vector<std::pair<std::string, std::string>> &msgs) {
    std::vector<llama_chat_message> raw(msgs.size());
    for (size_t i = 0; i < msgs.size(); i++) {
        raw[i].role = msgs[i].first.c_str();
        raw[i].content = msgs[i].second.c_str();
    }
    const char *tmpl = llama_model_chat_template(engine->model, nullptr);
    if (tmpl && tmpl[0]) {
        std::string buf(256 * 1024, '\0');
        int32_t wrote = llama_chat_apply_template(tmpl, raw.data(), raw.size(), true, buf.data(), (int32_t)buf.size());
        if (wrote > 0 && wrote < (int32_t)buf.size()) {
            buf.resize((size_t)wrote);
            return buf;
        }
    }
    return manual_chat(msgs);
}

static std::vector<llama_token> tokenize(const llama_vocab *vocab, const std::string &text) {
    int32_t n = llama_tokenize(vocab, text.c_str(), (int32_t)text.size(), nullptr, 0, false, true);
    if (n == INT32_MIN) return {};
    n = std::abs(n);
    std::vector<llama_token> tokens((size_t)n);
    if (n == 0) return tokens;
    if (llama_tokenize(vocab, text.c_str(), (int32_t)text.size(), tokens.data(), n, false, true) < 0) return {};
    return tokens;
}

br_engine *br_engine_load(const char *path, int n_ctx, int n_threads,
                          br_progress_fn on_load, void *user,
                          char *err, int errlen) {
    if (!path || !path[0]) {
        set_err(err, errlen, "Lipsește fișierul modelului.");
        return nullptr;
    }
    llama_backend_init();
    auto *pack = new std::pair<br_progress_fn, void *>(on_load, user);
    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;
    mparams.progress_callback = model_progress;
    mparams.progress_callback_user_data = pack;
    llama_model *model = llama_model_load_from_file(path, mparams);
    delete pack;
    if (!model) {
        set_err(err, errlen, "Modelul nu a putut fi încărcat. Șterge-l din Profil și descarcă-l din nou.");
        return nullptr;
    }
    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = (uint32_t)(n_ctx > 256 ? n_ctx : 2048);
    cparams.n_batch = 512;
    cparams.n_ubatch = 512;
    cparams.n_threads = n_threads > 0 ? n_threads : 4;
    cparams.n_threads_batch = cparams.n_threads;
    cparams.no_perf = true;
    auto *engine = new br_engine();
    engine->deadline = std::chrono::steady_clock::now() + std::chrono::hours(24);
    cparams.abort_callback = should_abort;
    cparams.abort_callback_data = engine;
    llama_context *ctx = llama_init_from_model(model, cparams);
    if (!ctx) {
        llama_model_free(model);
        delete engine;
        set_err(err, errlen, "Nu am putut pregăti contextul modelului.");
        return nullptr;
    }
    engine->model = model;
    engine->ctx = ctx;
    engine->vocab = llama_model_get_vocab(model);
    engine->n_ctx = (int)cparams.n_ctx;
    engine->n_threads = (int)cparams.n_threads;
    return engine;
}

void br_engine_free(br_engine *engine) {
    if (!engine) return;
    if (engine->ctx) llama_free(engine->ctx);
    if (engine->model) llama_model_free(engine->model);
    delete engine;
}

char *br_engine_chat(br_engine *engine,
                     const char *system_text,
                     const char **roles, const char **contents, int n_history,
                     const char *user_text,
                     int max_tokens,
                     br_text_fn on_partial, void *user,
                     char *err, int errlen) {
    if (!engine || !engine->ctx) {
        set_err(err, errlen, "Modelul nu este încărcat.");
        return nullptr;
    }
    if (max_tokens < 16) max_tokens = 16;
    if (max_tokens > 200) max_tokens = 200;
    engine->deadline = std::chrono::steady_clock::now() + std::chrono::seconds(240);

    std::vector<std::pair<std::string, std::string>> history;
    for (int i = 0; i < n_history; i++) {
        if (!roles || !contents || !roles[i] || !contents[i]) continue;
        history.push_back({roles[i], contents[i]});
    }
    std::string system = system_text ? system_text : "";
    std::string question = user_text ? user_text : "";

    std::vector<llama_token> prompt;
    for (int attempt = 0; attempt < 6; attempt++) {
        std::vector<std::pair<std::string, std::string>> msgs;
        msgs.push_back({"system", system});
        for (const auto &turn : history) msgs.push_back(turn);
        msgs.push_back({"user", question});
        std::string formatted = apply_template(engine, msgs);
        prompt = tokenize(engine->vocab, formatted);
        int budget = engine->n_ctx - max_tokens - 8;
        if ((int)prompt.size() > 0 && (int)prompt.size() <= budget) break;
        if (!history.empty()) {
            history.erase(history.begin());
            continue;
        }
        if (system.size() > 800) {
            system.resize(system.size() / 2);
            continue;
        }
        set_err(err, errlen, "Întrebarea și versetele nu încap în model. Formulează mai pe scurt.");
        return nullptr;
    }
    if (prompt.empty()) {
        set_err(err, errlen, "Nu am putut pregăti întrebarea.");
        return nullptr;
    }

    llama_memory_t mem = llama_get_memory(engine->ctx);
    if (mem) llama_memory_clear(mem, true);

    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    llama_sampler *smpl = llama_sampler_chain_init(sparams);
    int32_t n_vocab = llama_vocab_n_tokens(engine->vocab);
    llama_sampler_chain_add(smpl, llama_sampler_init_penalties(n_vocab, 64, 1.12f, 0.0f, 0.0f));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.4f));
    llama_sampler_chain_add(smpl, llama_sampler_init_dist((uint32_t)std::chrono::steady_clock::now().time_since_epoch().count()));

    llama_batch_ext *batch = llama_batch_ext_init(engine->ctx);
    const int chunk = 256;
    bool failed = false;
    for (int i = 0; i < (int)prompt.size();) {
        int n = std::min(chunk, (int)prompt.size() - i);
        bool last = i + n == (int)prompt.size();
        batch_tokens(batch, prompt.data() + i, n, (llama_pos)i, last);
        if (llama_process(engine->ctx, LLAMA_PROCESS_TYPE_DECODE, batch) != 0) {
            failed = true;
            break;
        }
        i += n;
    }

    std::string answer;
    if (!failed) {
        int n_pos = (int)prompt.size();
        for (int g = 0; g < max_tokens; g++) {
            if (std::chrono::steady_clock::now() > engine->deadline) break;
            llama_token id = llama_sampler_sample(smpl, engine->ctx, -1);
            if (llama_vocab_is_eog(engine->vocab, id)) break;
            answer += token_piece(engine->vocab, id);
            if (on_partial) {
                std::string shown = valid_prefix(answer);
                if (!shown.empty()) on_partial(shown.c_str(), user);
            }
            if (n_pos >= engine->n_ctx - 2) break;
            batch_tokens(batch, &id, 1, (llama_pos)n_pos, true);
            if (llama_process(engine->ctx, LLAMA_PROCESS_TYPE_DECODE, batch) != 0) {
                set_err(err, errlen, "Generarea s-a oprit înainte de sfârșit.");
                failed = true;
                break;
            }
            n_pos += 1;
        }
    } else if (!err || !err[0]) {
        set_err(err, errlen, "Modelul nu a putut citi versetele.");
    }

    llama_batch_ext_free(batch);
    llama_sampler_free(smpl);

    if (failed && answer.empty()) return nullptr;
    std::string shown = valid_prefix(answer);
    while (!shown.empty() && (shown.back() == '\n' || shown.back() == ' ')) shown.pop_back();
    if (shown.empty()) {
        set_err(err, errlen, "Modelul a răspuns gol. Încearcă din nou.");
        return nullptr;
    }
    char *out = (char *)std::malloc(shown.size() + 1);
    if (!out) {
        set_err(err, errlen, "Memorie insuficientă.");
        return nullptr;
    }
    std::memcpy(out, shown.data(), shown.size() + 1);
    return out;
}
