#!/bin/sh
# Hermes harness bootstrap — runs ONCE on first boot, as root, cwd /workspace, sh.
# Installs the Hermes CLI, then fills the placeholders in the COMMITTED seed config
# /workspace/.hermes/config.yaml. Hermes is fully FILE-based: it reads
# model/provider/skin from that file, so there is NO env-based config to defer to
# launch.sh. launch.sh re-seds the display.skin line each launch so a theme toggle
# takes effect on relaunch.
set -e

# --- install ----------------------------------------------------------------
# --skip-setup: the Nous installer otherwise runs an INTERACTIVE `hermes setup`
# wizard that reads /dev/tty and blocks bootstrap.sh forever (the dispatcher never
# reaches its launch loop). We seed config.yaml ourselves below, so skip the wizard.
# Redirect the installer's output to a log, NOT the terminal: the Nous install.sh
# apt-installs a large X11/font/ffmpeg stack and downloads Chromium, emitting
# hundreds of KB of "Get:/Unpacking/Setting up" lines. That fills the in-VM
# bridge's scrollback, and on the exit->bash reconnect the bridge REPLAYS that
# whole buffer — flooding the fresh socket so the sandboxd:validate exitToShell
# probe (a single `echo` in the dropped bash) is buried and bash looks dead. The
# other harnesses install one quiet npm/binary, so their replay is tiny; keep
# hermes's bootstrap equally quiet. `|| true` so a non-zero installer exit can't
# abort bootstrap (which would drop the once-only marker and re-run everything).
if ! command -v hermes >/dev/null 2>&1; then
  # --skip-browser: do NOT install Playwright/Chromium + the apt X11/font/ffmpeg
  # stack. That download is minutes long and, when it races the sandboxd:validate
  # checks (esp. under concurrency), the harness isn't fully up — notStuck renders
  # a sparse screen, resize can't reflow, and the exit cycle lands mid-install.
  # The browser/computer_use toolsets are disabled in config.yaml, so Chromium is
  # never used anyway. --non-interactive skips any input-needing stage.
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
    | bash -s -- --skip-setup --skip-browser --non-interactive \
      >/var/log/hermes-install.log 2>&1 || true
fi

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /workspace/AGENTS.md

# --- proxy-routed config ----------------------------------------------------
# Fill the seed config's placeholders. Hermes declares a user `tribes` provider in
# config.yaml's providers map and points model.provider at it (the built-in
# openai-api provider has a hardcoded Nous baseUrl, so an env override never takes
# effect — this MUST be a file). transport: chat_completions makes the OpenAI SDK
# append /chat/completions to `api`. We omit a provider `models` list so the picker
# discovers the full catalog from the proxy's GET /models; model.default preselects
# ours. Skip gracefully if the proxy env is absent (CLI falls back to user creds).
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ]; then
  sed -i "s|__TRIBES_PROXY__|${API_BASE_URL}/llm/proxy|g" /workspace/.hermes/config.yaml
  sed -i "s|__TRIBES_TOKEN__|$TRIBES_API_KEY|g" /workspace/.hermes/config.yaml
  sed -i "s|__TRIBES_MODEL__|$TRIBES_LLM_MODEL|g" /workspace/.hermes/config.yaml
  # Resolve the create-time skin now so no __TRIBES_SKIN__ placeholder reaches the
  # safety net below (launch.sh still re-seds the generic `skin:` line each launch
  # so a later theme toggle takes effect on relaunch).
  skin=$([ "$TRIBES_THEME" = light ] && echo daylight || echo default)
  sed -i "s|^  skin:.*|  skin: $skin|" /workspace/.hermes/config.yaml
else
  # No proxy env (BYO key) — drop the model:/providers: blocks so hermes falls back
  # to its built-in Nous provider/OAuth, but KEEP a skin-only display block: the
  # theme is independent of our proxy and a light-mode user must still get the
  # daylight skin. Resolve the skin now and rewrite the file to ONLY the display
  # block (no raw __TRIBES_* survives; launch.sh re-seds the same `skin:` line).
  skin=$([ "$TRIBES_THEME" = light ] && echo daylight || echo default)
  # Keep the same agent.disabled_toolsets suppression as the committed config (see
  # config.yaml) so a BYO box also avoids the first-run browser/tts/media install
  # storm that breaks exit->bash->relaunch.
  printf 'display:\n  skin: %s\nagent:\n  disabled_toolsets:\n    - browser\n    - computer_use\n    - tts\n    - video\n    - video_gen\n    - image_gen\n    - vision\n    - spotify\n' "$skin" >/workspace/.hermes/config.yaml
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /workspace may survive with a raw
# __TRIBES_* placeholder (broken/invalid config). AGENTS.md only carries
# __HOST__, so it is not matched.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /workspace 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done
