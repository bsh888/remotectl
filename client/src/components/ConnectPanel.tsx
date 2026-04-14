import { useEffect, useRef, useState } from 'react'
import { useI18n } from '../i18n'

export interface HistoryEntry {
  deviceID: string
  password: string
  serverURL: string
  ts: number
}

const HISTORY_KEY = 'rc_history'
const MAX_HISTORY = 8

export function loadHistory(): HistoryEntry[] {
  try {
    return JSON.parse(localStorage.getItem(HISTORY_KEY) ?? '[]')
  } catch {
    return []
  }
}

export function saveHistory(history: HistoryEntry[], entry: HistoryEntry): HistoryEntry[] {
  const filtered = history.filter(
    h => !(h.deviceID === entry.deviceID && h.serverURL === entry.serverURL)
  )
  const updated = [entry, ...filtered].slice(0, MAX_HISTORY)
  localStorage.setItem(HISTORY_KEY, JSON.stringify(updated))
  return updated
}

interface Props {
  onConnect: (serverURL: string, deviceID: string, password: string) => void
  error: string
  connecting: boolean
  history: HistoryEntry[]
  onRemoveHistory: (deviceID: string, serverURL: string) => void
}

export default function ConnectPanel({ onConnect, error, connecting, history, onRemoveHistory }: Props) {
  const { t } = useI18n()
  const [serverURL, setServerURL] = useState(() => localStorage.getItem('rc_server') ?? 'http://localhost:8080')
  const [deviceID, setDeviceID] = useState(() => localStorage.getItem('rc_device') ?? '')
  const [password, setPassword] = useState('')
  const passwordRef = useRef<HTMLInputElement>(null)

  useEffect(() => { localStorage.setItem('rc_server', serverURL) }, [serverURL])
  useEffect(() => { localStorage.setItem('rc_device', deviceID) }, [deviceID])

  const fillFromHistory = (entry: HistoryEntry) => {
    setServerURL(entry.serverURL)
    setDeviceID(entry.deviceID)
    setPassword(entry.password)
    setTimeout(() => passwordRef.current?.focus(), 0)
  }

  const handleConnect = (e: React.FormEvent) => {
    e.preventDefault()
    onConnect(serverURL, deviceID, password)
  }

  return (
    <div style={styles.container}>
      <div style={styles.card}>
        <h1 style={styles.title}>🖥 RemoteCtl</h1>

        {history.length > 0 && (
          <div style={styles.historySection}>
            <div style={styles.historyLabel}>{t('recent')}</div>
            <div style={styles.historyList}>
              {history.map(entry => (
                <div
                  key={`${entry.serverURL}|${entry.deviceID}`}
                  style={styles.historyItem}
                  onClick={() => fillFromHistory(entry)}
                >
                  <div style={styles.historyItemMain}>
                    <span style={styles.historyDeviceID}>{entry.deviceID}</span>
                    <span style={styles.historyServer}>{entry.serverURL.replace(/^https?:\/\//, '')}</span>
                  </div>
                  <button
                    style={styles.historyRemoveBtn}
                    onClick={e => { e.stopPropagation(); onRemoveHistory(entry.deviceID, entry.serverURL) }}
                    title={t('remove')}
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        <form onSubmit={handleConnect} style={styles.form}>
          <label style={styles.label}>
            {t('server_url')}
            <input
              style={styles.input}
              value={serverURL}
              onChange={e => setServerURL(e.target.value)}
              placeholder="https://your-server:8443"
              required
            />
          </label>

          <label style={styles.label}>
            {t('device_id')}
            <input
              style={styles.input}
              value={deviceID}
              onChange={e => setDeviceID(e.target.value)}
              placeholder={t('device_id_hint')}
              required
            />
          </label>

          <label style={styles.label}>
            {t('connect_pwd')}
            <input
              ref={passwordRef}
              style={styles.input}
              type="password"
              value={password}
              onChange={e => setPassword(e.target.value)}
              placeholder={t('connect_pwd_hint')}
              required
            />
          </label>

          {error && <div style={styles.error}>{error}</div>}

          <button type="submit" style={styles.btnPrimary} disabled={connecting}>
            {connecting ? t('connecting') : t('connect')}
          </button>
        </form>
      </div>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    padding: 16,
  },
  card: {
    background: '#1e293b',
    borderRadius: 12,
    padding: 32,
    width: '100%',
    maxWidth: 480,
    boxShadow: '0 8px 32px rgba(0,0,0,0.4)',
  },
  title: {
    fontSize: 24,
    fontWeight: 700,
    marginBottom: 28,
    textAlign: 'center',
  },
  historySection: {
    marginBottom: 20,
  },
  historyLabel: {
    fontSize: 12,
    color: '#64748b',
    fontWeight: 600,
    letterSpacing: '0.05em',
    textTransform: 'uppercase' as const,
    marginBottom: 8,
  },
  historyList: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 6,
  },
  historyItem: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    background: '#0f172a',
    border: '1px solid #334155',
    borderRadius: 8,
    padding: '9px 12px',
    cursor: 'pointer',
    transition: 'border-color 0.15s',
  },
  historyItemMain: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 2,
    minWidth: 0,
  },
  historyDeviceID: {
    fontSize: 14,
    fontWeight: 600,
    color: '#e2e8f0',
    fontFamily: 'monospace',
    letterSpacing: '0.05em',
  },
  historyServer: {
    fontSize: 11,
    color: '#475569',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap' as const,
  },
  historyRemoveBtn: {
    background: 'none',
    border: 'none',
    color: '#475569',
    fontSize: 18,
    lineHeight: 1,
    cursor: 'pointer',
    padding: '0 2px',
    flexShrink: 0,
  },
  form: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 16,
  },
  label: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 6,
    fontSize: 13,
    color: '#94a3b8',
  },
  input: {
    background: '#0f172a',
    border: '1px solid #334155',
    borderRadius: 6,
    padding: '10px 12px',
    color: '#e2e8f0',
    fontSize: 14,
    outline: 'none',
  },
  btnPrimary: {
    background: '#3b82f6',
    color: '#fff',
    border: 'none',
    borderRadius: 6,
    padding: '12px',
    fontSize: 15,
    fontWeight: 600,
    cursor: 'pointer',
    marginTop: 4,
  },
  error: {
    background: '#450a0a',
    color: '#fca5a5',
    borderRadius: 6,
    padding: '10px 12px',
    fontSize: 13,
  },
}
