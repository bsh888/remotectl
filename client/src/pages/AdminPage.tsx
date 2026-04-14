import { useState, useEffect, useCallback } from 'react'
import { useI18n, LANG_NAMES, type Lang } from '../i18n'

interface AgentInfo {
  id: string
  name: string
  platform: string
  host_info: string
  viewer_count: number
}

interface TokenInfo {
  device_id: string
  secret: string
}

type AdminView = 'dashboard' | 'agents' | 'tokens'

function apiFetch(path: string, token: string, opts?: RequestInit) {
  return fetch(path, {
    ...opts,
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(opts?.headers || {}),
    },
  })
}

// ── Design tokens (map to CSS vars from index.html) ─────────────────────────
const V = {
  bg:         'var(--bg)',
  surface:    'var(--surface)',
  surface2:   'var(--surface-2)',
  surface3:   'var(--surface-3)',
  border:     'var(--border)',
  border2:    'var(--border-2)',
  border3:    'var(--border-3)',
  accent:     'var(--accent)',
  accentDim:  'var(--accent-dim)',
  accentBdr:  'var(--accent-bdr)',
  green:      'var(--green)',
  greenDim:   'var(--green-dim)',
  greenBdr:   'var(--green-bdr)',
  blue:       'var(--blue)',
  text1:      'var(--text-1)',
  text2:      'var(--text-2)',
  text3:      'var(--text-3)',
  mono:       'var(--mono)',
  sans:       'var(--sans)',
  display:    'var(--display)',
}

export default function AdminPage() {
  const { t, lang, setLang } = useI18n()
  const [token, setToken] = useState(() => sessionStorage.getItem('admin_token') || '')
  const [loginPwd, setLoginPwd] = useState('')
  const [loginErr, setLoginErr] = useState('')
  const [loginLoading, setLoginLoading] = useState(false)
  const [view, setView] = useState<AdminView>('dashboard')
  const [agents, setAgents] = useState<AgentInfo[]>([])
  const [tokens, setTokens] = useState<TokenInfo[]>([])
  const [showLang, setShowLang] = useState(false)

  const [addDeviceId, setAddDeviceId] = useState('')
  const [addSecret, setAddSecret] = useState('')
  const [addErr, setAddErr] = useState('')
  const [editId, setEditId] = useState<string | null>(null)
  const [editSecret, setEditSecret] = useState('')
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null)

  const logout = () => {
    sessionStorage.removeItem('admin_token')
    setToken('')
  }

  const fetchAgents = useCallback(async () => {
    if (!token) return
    try {
      const r = await apiFetch('/api/admin/agents', token)
      if (r.ok) setAgents(await r.json())
      else if (r.status === 401) logout()
    } catch {}
  }, [token])

  const fetchTokens = useCallback(async () => {
    if (!token) return
    try {
      const r = await apiFetch('/api/admin/tokens', token)
      if (r.ok) setTokens(await r.json())
      else if (r.status === 401) logout()
    } catch {}
  }, [token])

  useEffect(() => {
    if (!token) return
    fetchAgents()
    fetchTokens()
    const interval = setInterval(fetchAgents, 5000)
    return () => clearInterval(interval)
  }, [token, fetchAgents, fetchTokens])

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoginLoading(true)
    setLoginErr('')
    try {
      const r = await fetch('/api/admin/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: loginPwd }),
      })
      if (r.ok) {
        const d = await r.json()
        sessionStorage.setItem('admin_token', d.token)
        setToken(d.token)
      } else {
        setLoginErr(t('login_error'))
      }
    } catch {
      setLoginErr(t('login_error'))
    } finally {
      setLoginLoading(false)
    }
  }

  const handleAddToken = async (e: React.FormEvent) => {
    e.preventDefault()
    setAddErr('')
    try {
      const r = await apiFetch('/api/admin/tokens', token, {
        method: 'POST',
        body: JSON.stringify({ device_id: addDeviceId, secret: addSecret }),
      })
      if (r.ok) {
        setAddDeviceId(''); setAddSecret('')
        fetchTokens()
      } else {
        const d = await r.json()
        setAddErr(d.error || t('login_error'))
      }
    } catch { setAddErr(t('login_error')) }
  }

  const handleUpdateToken = async (deviceId: string) => {
    try {
      const r = await apiFetch(`/api/admin/tokens/${deviceId}`, token, {
        method: 'PUT',
        body: JSON.stringify({ secret: editSecret }),
      })
      if (r.ok) {
        setEditId(null); setEditSecret('')
        fetchTokens()
      }
    } catch {}
  }

  const handleDeleteToken = async (deviceId: string) => {
    try {
      const r = await apiFetch(`/api/admin/tokens/${deviceId}`, token, { method: 'DELETE' })
      if (r.ok) fetchTokens()
    } catch {}
  }

  // ── Login page ──────────────────────────────────────────────────────────────
  if (!token) {
    return (
      <div style={{
        minHeight: '100vh',
        background: V.bg,
        backgroundImage: `linear-gradient(${V.border} 1px, transparent 1px), linear-gradient(90deg, ${V.border} 1px, transparent 1px)`,
        backgroundSize: '40px 40px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontFamily: V.sans,
      }}>
        <div style={{ width: 400, animation: 'rc-fade-up 0.5s ease both' }}>
          {/* Logo mark */}
          <div style={{ marginBottom: 40, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
            <div style={{
              width: 48, height: 48, borderRadius: 12,
              background: V.accentDim, border: `1px solid ${V.accentBdr}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <svg viewBox="0 0 24 24" fill="none" stroke={V.accent} strokeWidth={2} style={{ width: 22, height: 22 }}>
                <rect x="2" y="3" width="20" height="14" rx="2"/>
                <path d="M8 21h8M12 17v4"/>
              </svg>
            </div>
            <div>
              <div style={{ fontFamily: V.display, fontSize: 20, fontWeight: 800, color: V.text1, textAlign: 'center', letterSpacing: '-0.02em' }}>
                RemoteCtl
              </div>
              <div style={{ fontSize: 12, color: V.text3, textAlign: 'center', letterSpacing: '0.1em', textTransform: 'uppercase', marginTop: 2 }}>
                {t('admin_title')}
              </div>
            </div>
          </div>

          {/* Card */}
          <div style={{
            background: V.surface,
            border: `1px solid ${V.border2}`,
            borderRadius: 16,
            padding: 32,
          }}>
            <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
              <div>
                <div style={{ fontSize: 12, color: V.text3, letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: 8, fontWeight: 600 }}>
                  {t('admin_password')}
                </div>
                <input
                  type="password"
                  value={loginPwd}
                  onChange={e => setLoginPwd(e.target.value)}
                  placeholder="••••••••"
                  autoFocus
                  style={inputStyle}
                />
              </div>
              {loginErr && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: V.accent, fontSize: 13, background: V.accentDim, border: `1px solid ${V.accentBdr}`, borderRadius: 8, padding: '10px 14px' }}>
                  <svg viewBox="0 0 16 16" fill="currentColor" style={{ width: 14, height: 14, flexShrink: 0 }}>
                    <path d="M8 1.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-3a.75.75 0 0 1 .75.75v2.5a.75.75 0 0 1-1.5 0v-2.5A.75.75 0 0 1 8 5Zm0 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"/>
                  </svg>
                  {loginErr}
                </div>
              )}
              <button type="submit" disabled={loginLoading} style={btnPrimary}>
                {loginLoading ? '…' : t('login')}
              </button>
            </form>

            {/* Lang switcher */}
            <div style={{ marginTop: 24, paddingTop: 20, borderTop: `1px solid ${V.border}`, display: 'flex', justifyContent: 'center', gap: 6 }}>
              {(['zh', 'en', 'zh_TW'] as Lang[]).map(l => (
                <button key={l} onClick={() => setLang(l)} style={{
                  background: l === lang ? V.accentDim : 'transparent',
                  border: `1px solid ${l === lang ? V.accentBdr : V.border}`,
                  borderRadius: 6, padding: '5px 12px', fontSize: 12,
                  color: l === lang ? V.accent : V.text3,
                  cursor: 'pointer', fontFamily: V.sans, transition: 'all 0.15s',
                }}>{LANG_NAMES[l]}</button>
              ))}
            </div>
          </div>
        </div>
      </div>
    )
  }

  // ── Sidebar nav items ────────────────────────────────────────────────────────
  const sideItems: { key: AdminView; label: string; icon: React.ReactNode }[] = [
    {
      key: 'dashboard', label: t('dashboard'),
      icon: <svg viewBox="0 0 16 16" fill="currentColor" style={{ width: 14, height: 14 }}>
        <path d="M2 2h5v5H2zm0 7h5v5H2zm7-7h5v5H9zm0 7h5v5H9z"/>
      </svg>
    },
    {
      key: 'agents', label: t('agents'),
      icon: <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} style={{ width: 14, height: 14 }}>
        <rect x="1" y="2" width="14" height="10" rx="1.5"/>
        <path d="M5 15h6M8 12v3"/>
      </svg>
    },
    {
      key: 'tokens', label: t('tokens'),
      icon: <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} style={{ width: 14, height: 14 }}>
        <circle cx="6" cy="8" r="3.5"/><path d="M8.5 8H15M12 6v4"/>
      </svg>
    },
  ]

  return (
    <div style={{ minHeight: '100vh', background: V.bg, fontFamily: V.sans, color: V.text1, display: 'flex', flexDirection: 'column' }}>

      {/* Delete confirmation modal */}
      {deleteTarget && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.7)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000,
          backdropFilter: 'blur(4px)',
        }} onClick={() => setDeleteTarget(null)}>
          <div style={{
            background: V.surface, border: `1px solid ${V.border2}`,
            borderRadius: 16, padding: 28, width: 360,
            boxShadow: '0 32px 64px rgba(0,0,0,0.6)',
            animation: 'rc-fade-up 0.2s ease both',
          }} onClick={e => e.stopPropagation()}>
            <div style={{ fontSize: 16, fontWeight: 700, marginBottom: 8, fontFamily: V.display }}>{t('delete_token_title')}</div>
            <div style={{ color: V.text2, fontSize: 13, marginBottom: 24, lineHeight: 1.6 }}>
              {t('delete_token_msg')}{' '}
              <span style={{ color: V.accent, fontFamily: V.mono, fontSize: 13 }}>{deleteTarget}</span>
            </div>
            <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <button onClick={() => setDeleteTarget(null)} style={btnSmallGray}>{t('cancel')}</button>
              <button onClick={() => { handleDeleteToken(deleteTarget); setDeleteTarget(null) }} style={btnSmallRed}>{t('confirm')}</button>
            </div>
          </div>
        </div>
      )}

      {/* Top bar */}
      <div style={{
        height: 56, background: V.surface, borderBottom: `1px solid ${V.border}`,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 20px', flexShrink: 0,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{
            width: 28, height: 28, borderRadius: 7,
            background: V.accentDim, border: `1px solid ${V.accentBdr}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg viewBox="0 0 16 16" fill="none" stroke={V.accent} strokeWidth={1.8} style={{ width: 13, height: 13 }}>
              <rect x="1" y="2" width="14" height="10" rx="1.5"/>
              <path d="M5 15h6M8 12v3"/>
            </svg>
          </div>
          <span style={{ fontFamily: V.display, fontWeight: 800, fontSize: 16, letterSpacing: '-0.01em' }}>
            RemoteCtl <span style={{ color: V.text3, fontWeight: 400, fontSize: 13 }}>{t('admin_title')}</span>
          </span>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          {/* Language switcher */}
          <div style={{ position: 'relative' }}>
            <button onClick={() => setShowLang(v => !v)} style={{
              background: 'transparent', border: `1px solid ${V.border2}`,
              borderRadius: 7, color: V.text2, padding: '6px 12px', fontSize: 12,
              cursor: 'pointer', fontFamily: V.sans, display: 'flex', alignItems: 'center', gap: 6,
            }}>
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.4} style={{ width: 13, height: 13 }}>
                <circle cx="8" cy="8" r="6.5"/><path d="M8 1.5C6 4 5 6 5 8s1 4 3 6.5M8 1.5C10 4 11 6 11 8s-1 4-3 6.5M1.5 8h13"/>
              </svg>
              {LANG_NAMES[lang]}
            </button>
            {showLang && (
              <div style={{
                position: 'absolute', top: 'calc(100% + 4px)', right: 0,
                background: V.surface2, border: `1px solid ${V.border2}`,
                borderRadius: 10, overflow: 'hidden', minWidth: 130, zIndex: 200,
                boxShadow: '0 12px 32px rgba(0,0,0,0.4)',
              }}>
                {(['zh', 'en', 'zh_TW'] as Lang[]).map(l => (
                  <button key={l} onClick={() => { setLang(l); setShowLang(false) }} style={{
                    padding: '9px 16px', fontSize: 13, cursor: 'pointer',
                    color: l === lang ? V.accent : V.text2,
                    fontWeight: l === lang ? 600 : 400,
                    background: 'transparent', border: 'none', width: '100%',
                    textAlign: 'left' as const, fontFamily: V.sans,
                  }}>{LANG_NAMES[l]}</button>
                ))}
              </div>
            )}
          </div>

          <button onClick={logout} style={{
            background: 'transparent', border: `1px solid ${V.border2}`,
            color: V.text2, borderRadius: 7, padding: '6px 14px',
            fontSize: 12, cursor: 'pointer', fontFamily: V.sans,
            transition: 'all 0.15s',
          }} onMouseEnter={e => { (e.target as HTMLElement).style.color = V.accent; (e.target as HTMLElement).style.borderColor = V.accentBdr }}
             onMouseLeave={e => { (e.target as HTMLElement).style.color = V.text2; (e.target as HTMLElement).style.borderColor = V.border2 }}>
            {t('logout')}
          </button>
        </div>
      </div>

      <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
        {/* Sidebar */}
        <div style={{
          width: 192, background: V.surface, borderRight: `1px solid ${V.border}`,
          padding: '20px 0', flexShrink: 0,
        }}>
          {sideItems.map(item => (
            <div key={item.key}
              onClick={() => {
                setView(item.key)
                if (item.key === 'agents') fetchAgents()
                if (item.key === 'tokens') fetchTokens()
              }}
              style={{
                padding: '10px 18px', cursor: 'pointer',
                display: 'flex', alignItems: 'center', gap: 10, fontSize: 13,
                background: view === item.key ? V.accentDim : 'transparent',
                color: view === item.key ? V.accent : V.text2,
                borderLeft: `2px solid ${view === item.key ? V.accent : 'transparent'}`,
                transition: 'all 0.15s',
              }}>
              {item.icon}
              <span style={{ fontWeight: view === item.key ? 600 : 400 }}>{item.label}</span>
            </div>
          ))}

          {/* Online indicator */}
          {agents.length > 0 && (
            <div style={{ margin: '20px 18px 0', padding: '12px', background: V.greenDim, border: `1px solid ${V.greenBdr}`, borderRadius: 10 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
                <div style={{ width: 6, height: 6, borderRadius: '50%', background: V.green, animation: 'rc-pulse-dot 2s infinite' }} />
                <span style={{ fontSize: 11, color: V.green, fontWeight: 600, letterSpacing: '0.06em', textTransform: 'uppercase' }}>Online</span>
              </div>
              <div style={{ fontFamily: V.mono, fontSize: 20, fontWeight: 600, color: V.text1 }}>{agents.length}</div>
            </div>
          )}
        </div>

        {/* Main content */}
        <div style={{ flex: 1, overflow: 'auto', padding: 28 }}>

          {/* Dashboard */}
          {view === 'dashboard' && (
            <div>
              <div style={{ marginBottom: 28 }}>
                <h2 style={{ fontFamily: V.display, fontSize: 22, fontWeight: 800, letterSpacing: '-0.02em', color: V.text1, margin: 0 }}>{t('dashboard')}</h2>
              </div>

              {/* Stat cards */}
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 1, marginBottom: 28, background: V.border, borderRadius: 14, overflow: 'hidden', border: `1px solid ${V.border}` }}>
                {[
                  { label: t('online_devices'), value: agents.length, color: V.green, dim: V.greenDim, bdr: V.greenBdr, icon: <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} style={{ width: 16, height: 16 }}><rect x="1" y="2" width="14" height="10" rx="1.5"/><path d="M5 15h6M8 12v3"/></svg> },
                  { label: t('configured_tokens'), value: tokens.length, color: V.blue, dim: 'rgba(91,168,255,0.1)', bdr: 'rgba(91,168,255,0.25)', icon: <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} style={{ width: 16, height: 16 }}><circle cx="6" cy="8" r="3.5"/><path d="M8.5 8H15M12 6v4"/></svg> },
                  { label: t('total_viewers'), value: agents.reduce((s, a) => s + a.viewer_count, 0), color: V.accent, dim: V.accentDim, bdr: V.accentBdr, icon: <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} style={{ width: 16, height: 16 }}><path d="M1 8s3-5 7-5 7 5 7 5-3 5-7 5-7-5-7-5Z"/><circle cx="8" cy="8" r="2"/></svg> },
                ].map(card => (
                  <div key={card.label} style={{ background: V.surface, padding: 24 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                      <div>
                        <div style={{ fontSize: 11, color: V.text3, letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 600, marginBottom: 10 }}>{card.label}</div>
                        <div style={{ fontFamily: V.mono, fontSize: 32, fontWeight: 600, color: V.text1 }}>{card.value}</div>
                      </div>
                      <div style={{ color: card.color, background: card.dim, border: `1px solid ${card.bdr}`, borderRadius: 8, width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        {card.icon}
                      </div>
                    </div>
                  </div>
                ))}
              </div>

              {agents.length > 0 && (
                <div>
                  <SectionLabel>{t('online_devices')}</SectionLabel>
                  <AgentsTable agents={agents} />
                </div>
              )}
            </div>
          )}

          {/* Agents */}
          {view === 'agents' && (
            <div>
              <div style={{ marginBottom: 28, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <h2 style={{ fontFamily: V.display, fontSize: 22, fontWeight: 800, letterSpacing: '-0.02em', margin: 0 }}>{t('agents')}</h2>
                <div style={{ fontSize: 12, color: V.text3, fontFamily: V.mono }}>
                  {agents.length} {agents.length === 1 ? 'device' : 'devices'}
                </div>
              </div>
              <AgentsTable agents={agents} />
            </div>
          )}

          {/* Tokens */}
          {view === 'tokens' && (
            <div>
              <div style={{ marginBottom: 28, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <h2 style={{ fontFamily: V.display, fontSize: 22, fontWeight: 800, letterSpacing: '-0.02em', margin: 0 }}>{t('tokens')}</h2>
                <div style={{ fontSize: 12, color: V.text3, fontFamily: V.mono }}>{tokens.length} entries</div>
              </div>

              {/* Add form */}
              <div style={{ background: V.surface, border: `1px solid ${V.border2}`, borderRadius: 14, padding: 22, marginBottom: 20 }}>
                <div style={{ fontSize: 11, color: V.text3, letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 600, marginBottom: 14 }}>{t('add_token')}</div>
                <form onSubmit={handleAddToken} style={{ display: 'flex', gap: 10, flexWrap: 'wrap' as const }}>
                  <input
                    value={addDeviceId} onChange={e => setAddDeviceId(e.target.value)}
                    placeholder={t('device_id_label')}
                    style={{ ...inputStyle, fontFamily: V.mono, flex: '1 1 150px' }}
                  />
                  <input
                    value={addSecret} onChange={e => setAddSecret(e.target.value)}
                    placeholder={t('secret_label')}
                    style={{ ...inputStyle, fontFamily: V.mono, flex: '2 1 200px' }}
                  />
                  <button type="submit" style={btnPrimary}>{t('add')}</button>
                </form>
                {addErr && <div style={{ color: V.accent, fontSize: 12, marginTop: 10 }}>{addErr}</div>}
              </div>

              {/* Tokens table */}
              <DataTable>
                <thead>
                  <tr style={{ borderBottom: `1px solid ${V.border}` }}>
                    {[t('device_id_col'), t('host_info'), t('secret_label'), ''].map((h, i) => (
                      <TH key={i}>{h}</TH>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {tokens.length === 0 && (
                    <tr><td colSpan={4} style={{ padding: 40, textAlign: 'center', color: V.text3, fontSize: 13 }}>{t('no_tokens')}</td></tr>
                  )}
                  {tokens.map(tk => {
                    const online = agents.find(a => a.id === tk.device_id)
                    return (
                      <tr key={tk.device_id} style={{ borderBottom: `1px solid ${V.border}` }}>
                        <td style={{ padding: '12px 18px', fontFamily: V.mono, color: V.accent, fontSize: 13 }}>{tk.device_id}</td>
                        <td style={{ padding: '12px 18px' }}>
                          {online ? (
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                              <div style={{ width: 6, height: 6, borderRadius: '50%', background: V.green, flexShrink: 0, animation: 'rc-pulse-dot 2s infinite' }} />
                              <div>
                                <div style={{ color: V.text1, fontSize: 13, fontWeight: 500 }}>
                                  {online.host_info ? online.host_info.split(' · ')[0] : (online.name || online.id)}
                                </div>
                                {online.host_info?.includes(' · ') && (
                                  <div style={{ color: V.text3, fontSize: 11, marginTop: 1 }}>
                                    {online.host_info.split(' · ').slice(1).join(' · ')}
                                  </div>
                                )}
                              </div>
                            </div>
                          ) : (
                            <span style={{ color: V.text3, fontSize: 13 }}>—</span>
                          )}
                        </td>
                        <td style={{ padding: '12px 18px', fontFamily: V.mono, color: V.text2, fontSize: 12 }}>
                          {editId === tk.device_id ? (
                            <input
                              value={editSecret} onChange={e => setEditSecret(e.target.value)}
                              placeholder={t('secret_label')}
                              autoFocus
                              style={{ ...inputStyle, width: 240, fontFamily: V.mono }}
                            />
                          ) : tk.secret}
                        </td>
                        <td style={{ padding: '12px 18px' }}>
                          <div style={{ display: 'flex', gap: 6 }}>
                            {editId === tk.device_id ? (
                              <>
                                <button onClick={() => handleUpdateToken(tk.device_id)} style={btnSmallGreen}>{t('save')}</button>
                                <button onClick={() => setEditId(null)} style={btnSmallGray}>{t('cancel')}</button>
                              </>
                            ) : (
                              <>
                                <button onClick={() => { setEditId(tk.device_id); setEditSecret('') }} style={btnSmallBlue}>{t('edit')}</button>
                                <button onClick={() => setDeleteTarget(tk.device_id)} style={btnSmallRed}>{t('delete')}</button>
                              </>
                            )}
                          </div>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </DataTable>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

// ── Sub-components ────────────────────────────────────────────────────────────

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ fontSize: 11, color: 'var(--text-3)', letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 600, marginBottom: 12 }}>
      {children}
    </div>
  )
}

function DataTable({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ background: 'var(--surface)', border: `1px solid var(--border-2)`, borderRadius: 14, overflow: 'hidden' }}>
      <table style={{ width: '100%', borderCollapse: 'collapse' }}>{children}</table>
    </div>
  )
}

function TH({ children }: { children: React.ReactNode }) {
  return (
    <th style={{ padding: '12px 18px', textAlign: 'left', color: 'var(--text-3)', fontSize: 11, fontWeight: 600, letterSpacing: '0.06em', textTransform: 'uppercase' }}>
      {children}
    </th>
  )
}

function AgentsTable({ agents }: { agents: AgentInfo[] }) {
  const { t } = useI18n()

  const platformIcon = (p: string) => {
    if (p.includes('darwin') || p.includes('mac')) return (
      <svg viewBox="0 0 24 24" fill="currentColor" style={{ width: 14, height: 14, color: 'var(--text-2)' }}>
        <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.54 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/>
      </svg>
    )
    if (p.includes('windows')) return (
      <svg viewBox="0 0 24 24" style={{ width: 14, height: 14 }}>
        <path fill="#F25022" d="M1 1h10v10H1z"/>
        <path fill="#7FBA00" d="M13 1h10v10H13z"/>
        <path fill="#00A4EF" d="M1 13h10v10H1z"/>
        <path fill="#FFB900" d="M13 13h10v10H13z"/>
      </svg>
    )
    return (
      <svg viewBox="0 0 24 24" fill="currentColor" style={{ width: 14, height: 14, color: 'var(--text-2)' }}>
        <path d="M12.504 0c-.155 0-.315.008-.48.021C7.576.155 3.546 2.636 1.516 6.459C-.525 10.333-.451 14.858 1.706 18.7c2.199 3.896 6.228 6.296 10.7 6.3C17.84 25.006 22.7 20.76 23.945 15h-5.024c-1.063 3.343-4.158 5.777-7.917 5.777C6.53 20.777 2.5 16.776 2.5 12s4.03-8.777 8.504-8.777c2.104 0 4.024.71 5.546 1.872l-2.44 2.45A7.36 7.36 0 0 0 11.004 6C8.076 6 5.7 8.15 5.7 12s2.376 6 5.304 6c2.14 0 3.986-1.238 4.855-3.044h-4.855v-3.756h8.996C21 12.5 21 13 21 13.5c0 5.753-4.695 10.5-10.496 10.5C4.698 24 0 19.307 0 12.5 0 5.693 4.7 1 10.504 1c2.21 0 4.26.7 5.956 1.877l.044-.053z"/>
      </svg>
    )
  }

  return (
    <DataTable>
      <thead>
        <tr style={{ borderBottom: `1px solid var(--border)` }}>
          {[t('device_id_col'), t('host_info'), t('viewers')].map(h => <TH key={h}>{h}</TH>)}
        </tr>
      </thead>
      <tbody>
        {agents.length === 0 && (
          <tr><td colSpan={3} style={{ padding: 40, textAlign: 'center', color: 'var(--text-3)', fontSize: 13 }}>{t('no_agents')}</td></tr>
        )}
        {agents.map(a => (
          <tr key={a.id} style={{ borderBottom: `1px solid var(--border)` }}>
            <td style={{ padding: '12px 18px', fontFamily: 'var(--mono)', color: 'var(--accent)', fontSize: 13 }}>{a.id}</td>
            <td style={{ padding: '12px 18px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                {platformIcon(a.platform)}
                <div>
                  <div style={{ color: 'var(--text-1)', fontSize: 13, fontWeight: 500 }}>
                    {a.host_info ? a.host_info.split(' · ')[0] : (a.name || a.id)}
                  </div>
                  {a.host_info?.includes(' · ') && (
                    <div style={{ color: 'var(--text-3)', fontSize: 11, marginTop: 2 }}>
                      {a.host_info.split(' · ').slice(1).join(' · ')}
                    </div>
                  )}
                </div>
              </div>
            </td>
            <td style={{ padding: '12px 18px' }}>
              <span style={{
                background: a.viewer_count > 0 ? 'var(--green-dim)' : 'rgba(69,82,106,0.15)',
                color: a.viewer_count > 0 ? 'var(--green)' : 'var(--text-3)',
                border: `1px solid ${a.viewer_count > 0 ? 'var(--green-bdr)' : 'var(--border)'}`,
                borderRadius: 100, padding: '3px 10px', fontSize: 12, fontWeight: 600,
                fontFamily: 'var(--mono)',
              }}>
                {a.viewer_count > 0 ? a.viewer_count : '—'}
              </span>
            </td>
          </tr>
        ))}
      </tbody>
    </DataTable>
  )
}

// ── Shared styles ─────────────────────────────────────────────────────────────

const inputStyle: React.CSSProperties = {
  background: 'var(--surface-2)',
  border: '1px solid var(--border-2)',
  borderRadius: 8,
  padding: '9px 13px',
  color: 'var(--text-1)',
  fontSize: 13,
  outline: 'none',
  fontFamily: 'var(--sans)',
  minWidth: 0,
}

const btnPrimary: React.CSSProperties = {
  background: 'var(--accent)',
  border: 'none',
  borderRadius: 8,
  padding: '9px 20px',
  color: '#fff',
  fontWeight: 700,
  fontSize: 13,
  cursor: 'pointer',
  letterSpacing: '0.01em',
  whiteSpace: 'nowrap',
  fontFamily: 'var(--sans)',
}

const btnSmallBlue: React.CSSProperties = {
  background: 'rgba(91,168,255,0.08)', border: '1px solid rgba(91,168,255,0.2)',
  color: 'var(--blue)', borderRadius: 6, padding: '5px 12px', fontSize: 12,
  cursor: 'pointer', fontWeight: 500, fontFamily: 'var(--sans)',
}
const btnSmallRed: React.CSSProperties = {
  background: 'var(--accent-dim)', border: '1px solid var(--accent-bdr)',
  color: 'var(--accent)', borderRadius: 6, padding: '5px 12px', fontSize: 12,
  cursor: 'pointer', fontWeight: 500, fontFamily: 'var(--sans)',
}
const btnSmallGreen: React.CSSProperties = {
  background: 'var(--green-dim)', border: '1px solid var(--green-bdr)',
  color: 'var(--green)', borderRadius: 6, padding: '5px 12px', fontSize: 12,
  cursor: 'pointer', fontWeight: 500, fontFamily: 'var(--sans)',
}
const btnSmallGray: React.CSSProperties = {
  background: 'var(--surface-3)', border: '1px solid var(--border-2)',
  color: 'var(--text-2)', borderRadius: 6, padding: '5px 12px', fontSize: 12,
  cursor: 'pointer', fontWeight: 500, fontFamily: 'var(--sans)',
}
