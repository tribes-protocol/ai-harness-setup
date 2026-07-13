/**
 * Toast the human in the zipbox browser terminal when Pi finishes a turn.
 *
 * Pi has no built-in notification channel (unlike claude/grok/codex, which are
 * configured via their own settings), but it owns its pty -- so a plain stdout
 * write lands directly in the terminal. No /proc walk is needed here; that only
 * exists in `tribes-cli notify`, which agents spawn WITHOUT a controlling
 * terminal.
 *
 * OSC 777 is one of the escapes SandboxTerminal parses (alongside OSC 9 and 99).
 * It renders the body only -- the toast is titled with the sandbox name -- so
 * the title field below is never displayed.
 */
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent'

export default function (pi: ExtensionAPI): void {
  pi.on('agent_end', async () => {
    process.stdout.write('\x1b]777;notify;Pi;Ready for input\x07')
  })
}
