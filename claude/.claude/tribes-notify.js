#!/usr/bin/env node
// Claude Code `Notification` hook → a toast in the zipbox browser terminal.
//
// Claude's own notification channels can't reach us: `terminal_bell` emits a
// bare BEL, which the browser terminal ignores on purpose (readline rings it on
// every tab-completion), and `kitty` emits `ESC ] 9 ; 4 ; 0 ; BEL` — a ConEmu
// progress sequence with no message body. So we emit the notification ourselves.
//
// Claude runs a hook with no controlling terminal: fd 0/1/2 are pipes it
// captures, and opening /dev/tty fails with ENXIO. But the pty the user is
// looking at is still open, held by an ancestor — claude's own fd 1 is the pts
// slave. Walk the ppid chain to find it. Mirrors `src/utils/Tty.ts` in
// tribes-protocol/trading-harness; keep the two in step.
//
// Input: the hook payload on stdin, e.g. {"message":"Claude needs your input"}.

const { closeSync, constants, fstatSync, openSync, readFileSync, readlinkSync, writeSync } =
  require('node:fs')

const MAX_ANCESTRY_DEPTH = 32
const TITLE = 'Claude Code'
const TITLE_MAX_CHARS = 64
const BODY_MAX_CHARS = 200

// Anchored: never write an escape into something that isn't a terminal device.
const TTY_DEVICE_PATTERN = /^\/dev\/(?:pts\/\d+|tty\d*)$/u

function parentOf(pid) {
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, 'utf8')
    // Field 2 is the parenthesized comm and may contain spaces or ')', so parse
    // after the LAST ')': the fields there are state, then ppid.
    const fields = stat
      .slice(stat.lastIndexOf(')') + 1)
      .trim()
      .split(/\s+/u)
    const ppid = Number(fields[1])
    return Number.isInteger(ppid) && ppid > 0 ? ppid : undefined
  } catch {
    return undefined
  }
}

function terminalOf(pid) {
  for (const fd of [0, 1, 2]) {
    try {
      const target = readlinkSync(`/proc/${pid}/fd/${fd}`)
      if (TTY_DEVICE_PATTERN.test(target)) return target
    } catch {
      // fd closed, or not ours to inspect: try the next one.
    }
  }
  return undefined
}

/** Nearest ancestor still holding a pty. Starts at the parent: our fds are pipes. */
function findAncestorTerminal(startPid) {
  const seen = new Set()
  let pid = parentOf(startPid)
  for (let depth = 0; depth < MAX_ANCESTRY_DEPTH; depth += 1) {
    if (pid === undefined || pid <= 1) return undefined
    if (seen.has(pid)) return undefined
    seen.add(pid)
    const terminal = terminalOf(pid)
    if (terminal) return terminal
    pid = parentOf(pid)
  }
  return undefined
}

/**
 * Open O_WRONLY|O_NOCTTY and assert a character device — not writeFileSync,
 * which opens O_CREAT|O_TRUNC and would silently turn a stale path into a
 * regular file while reporting success.
 */
function writeToTerminalDevice(target, payload) {
  let fd
  try {
    fd = openSync(target, constants.O_WRONLY | constants.O_NOCTTY)
    if (!fstatSync(fd).isCharacterDevice()) return false
    writeSync(fd, payload)
    return true
  } catch {
    return false
  } finally {
    if (fd !== undefined) closeSync(fd)
  }
}

/** Drop control bytes (they'd terminate the OSC early) and the ';' field separator. */
function sanitizeField(raw, maxChars) {
  let out = ''
  for (const ch of raw) {
    const code = ch.codePointAt(0) ?? 0
    if (code < 0x20 || code === 0x7f) out += ' '
    else if (ch === ';') out += ','
    else out += ch
  }
  return out.trim().slice(0, maxChars)
}

function buildOscNotification(title, body) {
  return `\x1b]777;notify;${sanitizeField(title, TITLE_MAX_CHARS)};${sanitizeField(
    body,
    BODY_MAX_CHARS
  )}\x1b\\`
}

function readStdin() {
  try {
    return readFileSync(0, 'utf8')
  } catch {
    return ''
  }
}

function messageFrom(raw) {
  try {
    const message = JSON.parse(raw).message
    return typeof message === 'string' ? message : ''
  } catch {
    // Not JSON (a future payload shape, or none at all): treat it as the message.
    return raw
  }
}

const body = messageFrom(readStdin()).trim()
if (body.length > 0) {
  const payload = buildOscNotification(TITLE, body)
  const ancestor = findAncestorTerminal(process.pid)
  const targets = ['/dev/tty', ...(ancestor ? [ancestor] : [])]
  // Never fall back to stdout: claude captures a hook's stdout, so the escape
  // would be rendered as text in its own output pane rather than reaching xterm.
  targets.some((target) => writeToTerminalDevice(target, payload))
}
