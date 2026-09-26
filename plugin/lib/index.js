/**
 * dsh-copilot-key - manage the Copilot-key hook from inside DeepSeek Harness.
 *
 * Division of labour (2026-09-26):
 *   * DshCopilotKey.exe plus its logon scheduled task keep owning the key itself, so
 *     pressing the Copilot key still starts DeepSeek Harness when the app is closed;
 *   * this plugin manages that hook from the running app: status, start / stop /
 *     restart, manual trigger, config.ini editing and log tailing, exposed as
 *     copilot_key_* agent tools.
 *
 * The hook reads config.ini on every key press, so edits made here take effect on the
 * next press without restarting the hook.
 */
import { spawn, spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineTool } from '@deepseek-ai/dsh-tools'
import Schema from '@deepseek-ai/schemastery'

export const name = 'copilot-key'
export const inject = ['tools']

/** Trigger names the hook understands (see the hook/ directory in this repository). */
const TRIGGERS = ['winshift-f23', 'f23']

/**
 * Where the hook lives by default: $DSH_COPILOT_KEY_DIR when set, otherwise
 * <%USERPROFILE%>\copilot-key. No machine specific path is baked in; a profile can
 * still override `directory` with its own `- id: copilot-key` config row.
 */
function defaultDirectory() {
  const fromEnv = String(process.env.DSH_COPILOT_KEY_DIR || '').trim()
  if (fromEnv !== '') return fromEnv
  const home = process.env.USERPROFILE || process.env.HOME || '.'
  return join(home, 'copilot-key')
}

export const Config = Schema.object({
  directory: Schema.string().default(''),
  exeName: Schema.string().default('DshCopilotKey.exe'),
  taskName: Schema.string().default('DshCopilotKey'),
  logLines: Schema.number().default(10),
})

function textOutput() {
  return { schema: { type: 'string' }, render: (_args, value) => [{ type: 'text', text: String(value) }] }
}

/** One line per mount, so it is obvious when this plugin was last loaded. */
function noteMount(message) {
  try {
    const file = join(dirname(fileURLToPath(import.meta.url)), '..', 'plugin.log')
    writeFileSync(file, new Date().toISOString() + ' ' + message + String.fromCharCode(13) + String.fromCharCode(10), { flag: 'a' })
  } catch { /* diagnostics only */ }
}

export function apply(ctx, config) {
  noteMount('applied')
  const configured = String(config.directory || '').trim()
  const dir = configured !== '' ? configured : defaultDirectory()
  const exeName = String(config.exeName || 'DshCopilotKey.exe')
  const taskName = String(config.taskName || 'DshCopilotKey')
  const exe = join(dir, exeName)
  const ini = join(dir, 'config.ini')
  const LOG_FILES = { watcher: join(dir, 'watcher.log'), launcher: join(dir, 'launcher.log'), capture: join(dir, 'capture.log') }
  const defaultLines = Math.max(1, Math.min(200, Number(config.logLines) || 10))

  // ------------------------------------------------------------------ helpers

  /** Run one Windows tool without ever flashing a console window. */
  const run = (file, args, timeout = 15000) => spawnSync(file, args, { windowsHide: true, encoding: 'utf8', timeout })

  const parseIni = (text) => {
    const out = {}
    for (const raw of text.split(/\r?\n/)) {
      const line = raw.trim()
      if (line === '' || line.startsWith('#') || line.startsWith(';')) continue
      const eq = line.indexOf('=')
      if (eq < 1) continue
      out[line.slice(0, eq).trim()] = line.slice(eq + 1).trim()
    }
    return out
  }

  const readConfig = () => {
    if (!existsSync(ini)) throw new Error('config.ini not found at ' + ini + ' - is the Copilot-key tool installed?')
    return parseIni(readFileSync(ini, 'utf8'))
  }

  /** Rewrite individual keys in place, keeping every comment; one backup per call. */
  const writeConfig = (patch) => {
    const text = readFileSync(ini, 'utf8')
    const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14)
    const backup = ini + '.bak-' + stamp
    copyFileSync(ini, backup)
    const lines = text.split(/\r?\n/)
    const pending = new Map(Object.entries(patch))
    for (let i = 0; i < lines.length; i += 1) {
      const m = /^(\s*)([A-Za-z0-9_.-]+)(\s*)=/.exec(lines[i])
      if (m === null || !pending.has(m[2])) continue
      lines[i] = m[2] + ' = ' + pending.get(m[2])
      pending.delete(m[2])
    }
    while (lines.length > 0 && lines[lines.length - 1].trim() === '') lines.pop()
    for (const entry of pending) lines.push(entry[0] + ' = ' + entry[1])
    writeFileSync(ini, lines.join('\r\n') + '\r\n', 'utf8')
    return backup
  }

  /** PIDs of the running hook processes. */
  const hookPids = () => {
    const result = run('tasklist', ['/FI', 'IMAGENAME eq ' + exeName, '/FO', 'CSV', '/NH'])
    const pids = []
    for (const line of String(result.stdout || '').split(/\r?\n/)) {
      const m = /^"([^"]+)","(\d+)"/.exec(line.trim())
      if (m !== null && m[1].toLowerCase() === exeName.toLowerCase()) pids.push(Number(m[2]))
    }
    return pids
  }

  const taskState = () => {
    const result = run('schtasks', ['/Query', '/TN', taskName, '/FO', 'LIST'])
    const text = String(result.stdout || '') + String(result.stderr || '')
    if (result.status !== 0 && /not exist|cannot find|找不到|不存在/i.test(text)) return { registered: false }
    const line = text.split(/\r?\n/).find((entry) => /^\s*(Status|状态)\s*[:：]/i.test(entry))
    const state = line === undefined ? undefined : line.split(/[:：]/).slice(1).join(':').trim()
    return { registered: result.status === 0, ...(state === undefined || state === '' ? {} : { state }) }
  }

  const tail = (file, count) => {
    if (!existsSync(file)) return []
    const lines = readFileSync(file, 'utf8').split(/\r?\n/).filter((line) => line.trim() !== '')
    return lines.slice(-count)
  }

  const snapshot = () => {
    const pids = hookPids()
    const running = pids.length > 0
    const cfg = existsSync(ini) ? readConfig() : {}
    return { running, pids, task: taskState(), config: cfg, exe }
  }

  const describe = (state) => [
    'Copilot-key hook: ' + (state.running ? 'RUNNING (pid ' + state.pids.join(', ') + ')' : 'not running'),
    'Scheduled task ' + taskName + ': ' + (state.task.registered ? 'registered' + (state.task.state === undefined ? '' : ' (' + state.task.state + ')') : 'NOT registered'),
    'Trigger: ' + (state.config.trigger === undefined ? '(unset)' : state.config.trigger) + ' | dryrun: ' + (state.config.dryrun === undefined ? '0' : state.config.dryrun),
    'Target: port ' + (state.config.port === undefined ? '(unset)' : state.config.port) + ' | ' + (state.config.url === undefined ? '(unset)' : state.config.url),
    'Launcher: ' + (state.config.launcher === undefined ? '(unset)' : state.config.launcher) + (state.config.launcher !== undefined && !existsSync(state.config.launcher) ? '  [missing on disk]' : ''),
    'Executable: ' + state.exe + (existsSync(state.exe) ? '' : '  [MISSING]'),
  ].join('\n')

  const requireExe = () => {
    if (!existsSync(exe)) throw new Error('hook executable not found: ' + exe)
  }

  const stopHook = () => {
    const before = hookPids()
    if (before.length === 0) return { killed: [], before }
    run('taskkill', ['/IM', exeName, '/F'])
    const after = hookPids()
    return { killed: before.filter((pid) => !after.includes(pid)), before, after }
  }

  const startHook = () => {
    const already = hookPids()
    if (already.length > 0) return { started: false, pids: already, reason: 'already running' }
    requireExe()
    const child = spawn(exe, ['watch'], { detached: true, stdio: 'ignore', windowsHide: true })
    child.unref()
    return { started: true, pid: child.pid }
  }

  // -------------------------------------------------------------------- tools

  ctx.tools.register(defineTool({
    name: 'copilot_key_status',
    description: 'Report the Copilot-key hook: whether it is running (and its PIDs), the logon scheduled task state, and the effective config.ini values. Read-only.',
    parameters: {},
    output: textOutput(),
    async execute() {
      const state = snapshot()
      const recent = tail(LOG_FILES.watcher, 5)
      return describe(state)
        + (recent.length === 0 ? '\nwatcher.log: (no entries)' : '\nwatcher.log (last ' + recent.length + '):\n  ' + recent.join('\n  '))
    },
  }))

  ctx.tools.register(defineTool({
    name: 'copilot_key_start',
    description: 'Start the Copilot-key hook if it is not already running. The hook is a GUI process, so nothing flashes on screen.',
    parameters: {},
    output: textOutput(),
    async execute() {
      const result = startHook()
      if (!result.started) return 'Copilot-key hook is already running (pid ' + result.pids.join(', ') + ').'
      await new Promise((resolve) => setTimeout(resolve, 800))
      const pids = hookPids()
      return pids.length > 0
        ? 'Copilot-key hook started (pid ' + pids.join(', ') + ').'
        : 'Copilot-key hook was launched but no process is running now - check the executable and watcher.log.'
    },
  }))

  ctx.tools.register(defineTool({
    name: 'copilot_key_stop',
    description: 'Stop the Copilot-key hook (taskkill). Note: the DshCopilotKey scheduled task is configured to restart on failure, so it may come back; uninstall.ps1 removes it for good.',
    parameters: {},
    output: textOutput(),
    async execute() {
      const result = stopHook()
      if (result.before.length === 0) return 'Copilot-key hook was not running.'
      const survived = hookPids()
      return 'Stopped the Copilot-key hook (killed pid ' + result.killed.join(', ') + ').'
        + (survived.length > 0 ? ' It is running again already (pid ' + survived.join(', ') + ') - the scheduled task relaunched it.' : '')
    },
  }))

  ctx.tools.register(defineTool({
    name: 'copilot_key_restart',
    description: 'Restart the Copilot-key hook: stop every running hook process, then start one fresh.',
    parameters: {},
    output: textOutput(),
    async execute() {
      stopHook()
      await new Promise((resolve) => setTimeout(resolve, 500))
      const result = startHook()
      await new Promise((resolve) => setTimeout(resolve, 800))
      const pids = hookPids()
      return (result.started ? 'Restarted' : 'Start skipped (' + result.reason + ') for') + ' the Copilot-key hook; now running: '
        + (pids.length > 0 ? 'pid ' + pids.join(', ') : 'none')
    },
  }))

  ctx.tools.register(defineTool({
    name: 'copilot_key_trigger',
    description: 'Fire the Copilot-key action once, exactly as pressing the physical key would (DshCopilotKey.exe trigger). Requires the hook to be running.',
    parameters: {},
    output: textOutput(),
    async execute() {
      requireExe()
      const result = run(exe, ['trigger'], 20000)
      const text = String(result.stdout || '').trim()
      const error = String(result.stderr || '').trim()
      return 'trigger exit=' + result.status
        + (text === '' ? '' : '\nstdout: ' + text)
        + (error === '' ? '' : '\nstderr: ' + error)
        + '\n(If nothing happened, the hook is probably not running - call copilot_key_start first.)'
    },
  }))

  ctx.tools.register(defineTool({
    name: 'copilot_key_config',
    description: 'Read config.ini, or change one or more keys. The hook re-reads the file on every key press, so changes apply on the next press without restarting it. A timestamped backup is written next to the file.',
    parameters: {
      trigger: { type: 'string' },
      port: { type: 'integer' },
      url: { type: 'string' },
      launcher: { type: 'string' },
      dryrun: { type: 'string' },
    },
    output: textOutput(),
    async execute(args) {
      const patch = {}
      if (args.trigger !== undefined && args.trigger !== null && args.trigger !== '') {
        if (!TRIGGERS.includes(args.trigger)) throw new Error('trigger must be one of: ' + TRIGGERS.join(', '))
        patch.trigger = args.trigger
      }
      if (args.port !== undefined && args.port !== null) {
        const port = Number(args.port)
        if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('port must be an integer between 1 and 65535')
        patch.port = String(port)
      }
      if (args.url !== undefined && args.url !== null && args.url !== '') {
        if (!/^https?:\/\//i.test(args.url)) throw new Error('url must start with http:// or https://')
        patch.url = args.url
      }
      if (args.launcher !== undefined && args.launcher !== null && args.launcher !== '') patch.launcher = args.launcher
      if (args.dryrun !== undefined && args.dryrun !== null && args.dryrun !== '') {
        const value = String(args.dryrun).toLowerCase()
        if (!['0', '1', 'true', 'false'].includes(value)) throw new Error('dryrun must be 0/1 (or true/false)')
        patch.dryrun = value === '1' || value === 'true' ? '1' : '0'
      }
      const before = readConfig()
      if (Object.keys(patch).length === 0) {
        return 'config.ini (' + ini + '):\n' + Object.entries(before).map(([k, v]) => '  ' + k + ' = ' + v).join('\n')
      }
      const backup = writeConfig(patch)
      const after = readConfig()
      const changed = Object.keys(patch).map((key) => '  ' + key + ': ' + (before[key] === undefined ? '(unset)' : before[key]) + ' -> ' + after[key]).join('\n')
      return 'Updated ' + ini + '\n' + changed + '\nBackup: ' + backup
        + (patch.dryrun === '1' ? '\nNote: dryrun=1 means the key now only logs and does not launch anything.' : '')
    },
  }))

  ctx.tools.register(defineTool({
    name: 'copilot_key_log',
    description: 'Tail one of the Copilot-key logs: watcher (every key press), launcher (the cold-start script) or capture (raw key codes).',
    parameters: {
      file: { type: 'string', default: 'watcher' },
      lines: { type: 'integer', default: defaultLines },
    },
    output: textOutput(),
    async execute(args) {
      const key = String(args.file || 'watcher').toLowerCase()
      const file = LOG_FILES[key]
      if (file === undefined) throw new Error('file must be one of: ' + Object.keys(LOG_FILES).join(', '))
      const count = Math.max(1, Math.min(200, Number(args.lines) || defaultLines))
      const entries = tail(file, count)
      if (entries.length === 0) return file + ': (no entries)'
      return file + ' (last ' + entries.length + '):\n  ' + entries.join('\n  ')
    },
  }))
}
