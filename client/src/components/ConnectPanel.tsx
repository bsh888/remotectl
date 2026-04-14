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
    <div style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100%',
      padding: 20,
      background: 'var(--bg)',
    }}>
      <div style={{
        width: '100%',
        maxWidth: 440,
        animation: 'rc-fade-up 0.4s ease both',
      }}>
        {/* Header */}
        <div style={{ marginBottom: 28, display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{
            width: 40, height: 40, borderRadius: 10,
            background: 'var(--accent-dim)', border: '1px solid var(--accent-bdr)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            <svg viewBox="0 0 20 20" fill="none" stroke="var(--accent)" strokeWidth={1.8} style={{ width: 18, height: 18 }}>
              <rect x="1" y="3" width="18" height="12" rx="2"/>
              <path d="M7 18h6M10 15v3"/>
            </svg>
          </div>
          <div>
            <div style={{ fontFamily: 'var(--display)', fontWeight: 800, fontSize: 18, letterSpacing: '-0.02em', color: 'var(--text-1)' }}>
              RemoteCtl
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-3)', letterSpacing: '0.06em', textTransform: 'uppercase' }}>
              Remote Desktop
            </div>
          </div>
        </div>

        {/* Card */}
        <div style={{
          background: 'var(--surface)',
          border: '1px solid var(--border-2)',
          borderRadius: 16,
          overflow: 'hidden',
        }}>
          {/* Recent connections */}
          {history.length > 0 && (
            <div style={{ borderBottom: '1px solid var(--border)' }}>
              <div style={{ padding: '14px 20px 8px', fontSize: 10, color: 'var(--text-3)', fontWeight: 700, letterSpacing: '0.1em', textTransform: 'uppercase' }}>
                {t('recent')}
              </div>
              <div style={{ padding: '0 8px 8px' }}>
                {history.map(entry => (
                  <div
                    key={`${entry.serverURL}|${entry.deviceID}`}
                    onClick={() => fillFromHistory(entry)}
                    style={{
                      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                      padding: '8px 12px', borderRadius: 8, cursor: 'pointer',
                      transition: 'background 0.12s',
                    }}
                    onMouseEnter={e => (e.currentTarget.style.background = 'var(--surface-2)')}
                    onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
                      <div style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--border-3)', flexShrink: 0 }} />
                      <div style={{ minWidth: 0 }}>
                        <div style={{ fontFamily: 'var(--mono)', fontSize: 13, fontWeight: 600, color: 'var(--text-1)', letterSpacing: '0.04em' }}>
                          {entry.deviceID}
                        </div>
                        <div style={{ fontSize: 11, color: 'var(--text-3)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                          {entry.serverURL.replace(/^https?:\/\//, '')}
                        </div>
                      </div>
                    </div>
                    <button
                      onClick={e => { e.stopPropagation(); onRemoveHistory(entry.deviceID, entry.serverURL) }}
                      title={t('remove')}
                      style={{
                        background: 'none', border: 'none', color: 'var(--text-3)',
                        fontSize: 16, lineHeight: 1, cursor: 'pointer', padding: '2px 4px',
                        flexShrink: 0, borderRadius: 4, transition: 'color 0.12s',
                      }}
                      onMouseEnter={e => (e.currentTarget.style.color = 'var(--accent)')}
                      onMouseLeave={e => (e.currentTarget.style.color = 'var(--text-3)')}
                    >×</button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Form */}
          <form onSubmit={handleConnect} style={{ padding: 20, display: 'flex', flexDirection: 'column', gap: 14 }}>
            <FieldGroup label={t('server_url')}>
              <input
                style={inputStyle}
                value={serverURL}
                onChange={e => setServerURL(e.target.value)}
                placeholder="https://your-server:8443"
                required
              />
            </FieldGroup>

            <FieldGroup label={t('device_id')}>
              <input
                style={{ ...inputStyle, fontFamily: 'var(--mono)', letterSpacing: '0.06em' }}
                value={deviceID}
                onChange={e => setDeviceID(e.target.value)}
                placeholder={t('device_id_hint')}
                required
              />
            </FieldGroup>

            <FieldGroup label={t('connect_pwd')}>
              <input
                ref={passwordRef}
                style={inputStyle}
                type="password"
                value={password}
                onChange={e => setPassword(e.target.value)}
                placeholder={t('connect_pwd_hint')}
                required
              />
            </FieldGroup>

            {error && (
              <div style={{
                display: 'flex', alignItems: 'center', gap: 8,
                background: 'var(--accent-dim)', border: '1px solid var(--accent-bdr)',
                borderRadius: 8, padding: '10px 14px',
                color: 'var(--accent)', fontSize: 13,
              }}>
                <svg viewBox="0 0 16 16" fill="currentColor" style={{ width: 13, height: 13, flexShrink: 0 }}>
                  <path d="M8 1.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-3a.75.75 0 0 1 .75.75v2.5a.75.75 0 0 1-1.5 0v-2.5A.75.75 0 0 1 8 5Zm0 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"/>
                </svg>
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={connecting}
              style={{
                background: connecting ? 'var(--surface-3)' : 'var(--accent)',
                border: 'none', borderRadius: 10, padding: '12px',
                color: connecting ? 'var(--text-3)' : '#fff',
                fontWeight: 700, fontSize: 14, cursor: connecting ? 'not-allowed' : 'pointer',
                fontFamily: 'var(--sans)', letterSpacing: '0.01em',
                transition: 'all 0.15s',
                display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
              }}
            >
              {connecting ? (
                <>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} style={{ width: 14, height: 14, animation: 'rc-spin 0.8s linear infinite' }}>
                    <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/>
                  </svg>
                  {t('connecting')}
                </>
              ) : (
                <>
                  {t('connect')}
                  <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={2} style={{ width: 13, height: 13 }}>
                    <path d="M3 8h10M9 4l4 4-4 4"/>
                  </svg>
                </>
              )}
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}

function FieldGroup({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <div style={{ fontSize: 11, color: 'var(--text-3)', fontWeight: 600, letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: 7 }}>
        {label}
      </div>
      {children}
    </div>
  )
}

const inputStyle: React.CSSProperties = {
  width: '100%',
  boxSizing: 'border-box' as const,
  background: 'var(--surface-2)',
  border: '1px solid var(--border-2)',
  borderRadius: 9,
  padding: '10px 13px',
  color: 'var(--text-1)',
  fontSize: 14,
  outline: 'none',
  fontFamily: 'var(--sans)',
  transition: 'border-color 0.15s',
}
