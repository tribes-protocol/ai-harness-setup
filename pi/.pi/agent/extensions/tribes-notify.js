// Ping the terminal when pi needs the human, so a user who tabbed away is told
// the agent has stopped and is waiting on them.
//
// Pi has no built-in terminal notification — claude/grok/codex each take a config
// key for this, pi emits no OSC at all — so the escape has to come from here.
//
// agent_settled is the only correct event: it fires once the run has fully settled
// and no auto-retry, auto-compaction, or queued continuation is left to run.
// agent_end fires INSIDE that drain loop, so it would ping while pi is still
// working. agent_settled landed in pi 0.80.6 — on an older pi this extension loads
// and stays inert rather than notifying at the wrong moment.
//
// OSC 9 (`ESC ] 9 ; <text> BEL`). zipbox's SandboxTerminal ignores an OSC 9 payload
// that starts with `<digit>;` — that form is ConEmu progress, which pi-tui itself
// emits — so the text must not lead with a digit.
export default function (pi) {
  pi.on('agent_settled', () => {
    process.stdout.write('\u001b]9;pi is waiting for your input\u0007')
  })
}
