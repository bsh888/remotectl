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

  // Token form
  const [addDeviceId, setAddDeviceId] = useState('')
  const [addSecret, setAddSecret] = useState('')
  const [addErr, setAddErr] = useState('')
  const [editId, setEditId] = useState<string | null>(null)
  const [editSecret, setEditSecret] = useState('')

  // Delete confirmation modal
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

  // Styles
  const dark = '#0a0e1a'
  const surface = '#0f1629'
  const surface2 = '#141d35'
  const border = 'rgba(255,255,255,0.06)'
  const accent = '#6366f1'
  const textMuted = '#64748b'

  if (!token) {
    return (
      <div style={{
        minHeight:'100vh', background:dark,
        display:'flex', alignItems:'center', justifyContent:'center',
        fontFamily:'-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      }}>
        <div style={{
          background:surface, border:`1px solid ${border}`,
          borderRadius:20, padding:48, width:380,
        }}>
          <div style={{
            fontSize:24, fontWeight:700, marginBottom:8,
            background:'linear-gradient(135deg, #6366f1, #8b5cf6)',
            WebkitBackgroundClip:'text', WebkitTextFillColor:'transparent',
          }}>RemoteCtl {t('admin_title')}</div>
          <p style={{color:textMuted, fontSize:14, marginBottom:32}}>{t('admin_password')}</p>
          <form onSubmit={handleLogin}>
            <input
              type="password"
              value={loginPwd}
              onChange={e => setLoginPwd(e.target.value)}
              placeholder={t('admin_password')}
              autoFocus
              style={{
                width:'100%', boxSizing:'border-box' as const,
                background:'rgba(255,255,255,0.05)', border:`1px solid ${border}`,
                borderRadius:10, padding:'14px 16px', color:'#e2e8f0',
                fontSize:15, outline:'none', marginBottom:16,
              }}
            />
            {loginErr && <div style={{color:'#f87171', fontSize:13, marginBottom:12}}>{loginErr}</div>}
            <button type="submit" disabled={loginLoading} style={{
              width:'100%', background:'linear-gradient(135deg, #6366f1, #8b5cf6)',
              border:'none', borderRadius:10, padding:'14px',
              color:'white', fontWeight:600, fontSize:15, cursor:'pointer',
            }}>
              {loginLoading ? '…' : t('login')}
            </button>
          </form>
          {/* Language switcher on login page */}
          <div style={{marginTop:20, display:'flex', justifyContent:'center', gap:8}}>
            {(['zh','en','zh_TW'] as Lang[]).map(l => (
              <button key={l} onClick={() => setLang(l)} style={{
                background: l === lang ? 'rgba(99,102,241,0.2)' : 'transparent',
                border: '1px solid rgba(255,255,255,0.08)',
                borderRadius:6, padding:'4px 10px', fontSize:12,
                color: l === lang ? '#a5b4fc' : '#64748b',
                cursor:'pointer',
              }}>{LANG_NAMES[l]}</button>
            ))}
          </div>
        </div>
      </div>
    )
  }

  const sideItems: {key: AdminView; label: string; icon: string}[] = [
    { key: 'dashboard', label: t('dashboard'), icon: '📊' },
    { key: 'agents', label: t('agents'), icon: '🖥️' },
    { key: 'tokens', label: t('tokens'), icon: '🔑' },
  ]

  return (
    <div style={{
      minHeight:'100vh', background:dark,
      fontFamily:'-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      color:'#e2e8f0', display:'flex', flexDirection:'column',
    }}>
      {/* Delete confirmation modal */}
      {deleteTarget && (
        <div style={{
          position:'fixed', inset:0, background:'rgba(0,0,0,0.6)',
          display:'flex', alignItems:'center', justifyContent:'center',
          zIndex:1000,
        }} onClick={() => setDeleteTarget(null)}>
          <div style={{
            background:'#0f1629', border:'1px solid rgba(255,255,255,0.1)',
            borderRadius:16, padding:28, width:360,
            boxShadow:'0 24px 48px rgba(0,0,0,0.5)',
          }} onClick={e => e.stopPropagation()}>
            <div style={{fontSize:18, fontWeight:700, marginBottom:8}}>{t('delete_token_title')}</div>
            <div style={{color:'#94a3b8', fontSize:14, marginBottom:24, lineHeight:1.6}}>
              {t('delete_token_msg')} <span style={{color:'#a5b4fc', fontFamily:'monospace'}}>{deleteTarget}</span>
            </div>
            <div style={{display:'flex', gap:10, justifyContent:'flex-end'}}>
              <button onClick={() => setDeleteTarget(null)} style={btnSmallGray}>{t('cancel')}</button>
              <button onClick={() => { handleDeleteToken(deleteTarget); setDeleteTarget(null) }} style={{
                background:'rgba(248,113,113,0.15)', border:'1px solid rgba(248,113,113,0.3)',
                color:'#f87171', borderRadius:6, padding:'8px 18px', fontSize:13,
                cursor:'pointer', fontWeight:600,
              }}>{t('confirm')}</button>
            </div>
          </div>
        </div>
      )}

      {/* Top bar */}
      <div style={{
        height:60, background:surface, borderBottom:`1px solid ${border}`,
        display:'flex', alignItems:'center', justifyContent:'space-between',
        padding:'0 24px', flexShrink:0,
      }}>
        <span style={{
          fontSize:18, fontWeight:700,
          background:'linear-gradient(135deg, #6366f1, #8b5cf6)',
          WebkitBackgroundClip:'text', WebkitTextFillColor:'transparent',
        }}>RemoteCtl {t('admin_title')}</span>
        <div style={{display:'flex', alignItems:'center', gap:12}}>
          {/* Language switcher */}
          <div style={{position:'relative'}}>
            <button onClick={() => setShowLang(v => !v)} style={{
              background:'transparent', border:'1px solid rgba(255,255,255,0.1)',
              borderRadius:6, color:'#94a3b8', padding:'6px 12px', fontSize:13, cursor:'pointer',
            }}>
              🌐 {LANG_NAMES[lang]}
            </button>
            {showLang && (
              <div style={{
                position:'absolute', top:'100%', right:0, marginTop:4,
                background:'#1e293b', border:'1px solid rgba(255,255,255,0.1)',
                borderRadius:8, overflow:'hidden', minWidth:130, zIndex:200,
              }}>
                {(['zh','en','zh_TW'] as Lang[]).map(l => (
                  <button key={l} onClick={() => { setLang(l); setShowLang(false) }} style={{
                    padding:'10px 16px', fontSize:13, cursor:'pointer',
                    color: l === lang ? '#a5b4fc' : '#e2e8f0',
                    fontWeight: l === lang ? 600 : 400,
                    background:'transparent', border:'none', width:'100%', textAlign:'left' as const,
                  }}>{LANG_NAMES[l]}</button>
                ))}
              </div>
            )}
          </div>
          <button onClick={logout} style={{
            background:'rgba(248,113,113,0.1)', border:'1px solid rgba(248,113,113,0.2)',
            color:'#f87171', borderRadius:8, padding:'8px 16px',
            fontSize:13, cursor:'pointer',
          }}>{t('logout')}</button>
        </div>
      </div>

      <div style={{display:'flex', flex:1, overflow:'hidden'}}>
        {/* Sidebar */}
        <div style={{
          width:200, background:surface, borderRight:`1px solid ${border}`,
          padding:'16px 0', flexShrink:0,
        }}>
          {sideItems.map(item => (
            <div key={item.key}
              onClick={() => { setView(item.key); if(item.key==='agents') fetchAgents(); if(item.key==='tokens') fetchTokens() }}
              style={{
                padding:'12px 20px', cursor:'pointer', display:'flex',
                alignItems:'center', gap:10, fontSize:14,
                background: view===item.key ? 'rgba(99,102,241,0.12)' : 'transparent',
                color: view===item.key ? '#a5b4fc' : '#94a3b8',
                borderLeft: view===item.key ? `3px solid ${accent}` : '3px solid transparent',
                transition:'all 0.15s',
              }}>
              <span>{item.icon}</span>
              <span>{item.label}</span>
            </div>
          ))}
        </div>

        {/* Main */}
        <div style={{flex:1, overflow:'auto', padding:32}}>

          {/* Dashboard */}
          {view === 'dashboard' && (
            <div>
              <h2 style={{margin:'0 0 8px', fontSize:24, fontWeight:700}}>{t('dashboard')}</h2>
              <div style={{display:'grid', gridTemplateColumns:'repeat(auto-fit, minmax(200px,1fr))', gap:20, marginBottom:32}}>
                {[
                  { label: t('online_devices'), value: agents.length, color:'#6366f1', icon:'🖥️' },
                  { label: t('configured_tokens'), value: tokens.length, color:'#8b5cf6', icon:'🔑' },
                  { label: t('total_viewers'), value: agents.reduce((s,a) => s+a.viewer_count, 0), color:'#06b6d4', icon:'👁️' },
                ].map(card => (
                  <div key={card.label} style={{
                    background:surface2, border:`1px solid ${border}`,
                    borderRadius:16, padding:24,
                  }}>
                    <div style={{display:'flex', justifyContent:'space-between', alignItems:'flex-start'}}>
                      <div>
                        <div style={{color:textMuted, fontSize:13, marginBottom:8}}>{card.label}</div>
                        <div style={{fontSize:36, fontWeight:700, color:'#e2e8f0'}}>{card.value}</div>
                      </div>
                      <div style={{
                        fontSize:28, width:52, height:52, borderRadius:12,
                        background:`rgba(${card.color === '#6366f1' ? '99,102,241' : card.color === '#8b5cf6' ? '139,92,246' : '6,182,212'},0.12)`,
                        display:'flex', alignItems:'center', justifyContent:'center',
                      }}>{card.icon}</div>
                    </div>
                  </div>
                ))}
              </div>
              {agents.length > 0 && (
                <div>
                  <h3 style={{marginBottom:16, fontWeight:600}}>{t('online_devices')}</h3>
                  <AgentsTable agents={agents} />
                </div>
              )}
            </div>
          )}

          {/* Agents */}
          {view === 'agents' && (
            <div>
              <h2 style={{margin:'0 0 24px', fontSize:24, fontWeight:700}}>{t('agents')}</h2>
              <AgentsTable agents={agents} />
            </div>
          )}

          {/* Tokens */}
          {view === 'tokens' && (
            <div>
              <h2 style={{margin:'0 0 8px', fontSize:24, fontWeight:700}}>{t('tokens')}</h2>
              <p style={{color:textMuted, marginBottom:32, fontSize:14}}></p>

              {/* Add form */}
              <div style={{
                background:surface2, border:`1px solid ${border}`,
                borderRadius:16, padding:24, marginBottom:24,
              }}>
                <h3 style={{margin:'0 0 16px', fontWeight:600, fontSize:16}}>{t('add_token')}</h3>
                <form onSubmit={handleAddToken} style={{display:'flex', gap:12, flexWrap:'wrap' as const}}>
                  <input
                    value={addDeviceId} onChange={e => setAddDeviceId(e.target.value)}
                    placeholder={t('device_id_label')}
                    style={inputStyle}
                  />
                  <input
                    value={addSecret} onChange={e => setAddSecret(e.target.value)}
                    placeholder={t('secret_label')}
                    style={inputStyle}
                  />
                  <button type="submit" style={{
                    background:'linear-gradient(135deg,#6366f1,#8b5cf6)',
                    border:'none', borderRadius:8, padding:'10px 20px',
                    color:'white', fontWeight:600, cursor:'pointer', fontSize:14,
                    whiteSpace:'nowrap' as const,
                  }}>{t('add')}</button>
                </form>
                {addErr && <div style={{color:'#f87171', fontSize:13, marginTop:8}}>{addErr}</div>}
              </div>

              {/* Tokens table */}
              <div style={{
                background:surface2, border:`1px solid ${border}`,
                borderRadius:16, overflow:'hidden',
              }}>
                <table style={{width:'100%', borderCollapse:'collapse'}}>
                  <thead>
                    <tr style={{borderBottom:`1px solid ${border}`}}>
                      {[t('device_id_col'), t('host_info'), t('secret_label'), ''].map((h, i) => (
                        <th key={i} style={{padding:'14px 20px', textAlign:'left', color:textMuted, fontSize:13, fontWeight:600}}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {tokens.length === 0 && (
                      <tr><td colSpan={4} style={{padding:40, textAlign:'center', color:textMuted}}>{t('no_tokens')}</td></tr>
                    )}
                    {tokens.map(tk => {
                      const online = agents.find(a => a.id === tk.device_id)
                      return (
                      <tr key={tk.device_id} style={{borderBottom:`1px solid rgba(255,255,255,0.03)`}}>
                        <td style={{padding:'14px 20px', fontFamily:'monospace', color:'#a5b4fc'}}>{tk.device_id}</td>
                        <td style={{padding:'14px 20px'}}>
                          {online ? (
                            <div style={{display:'flex', alignItems:'center', gap:8}}>
                              <span style={{
                                width:7, height:7, borderRadius:'50%',
                                background:'#4ade80', display:'inline-block', flexShrink:0,
                              }}/>
                              <div>
                                <div style={{color:'#e2e8f0', fontSize:13, fontWeight:500}}>
                                  {online.host_info ? online.host_info.split(' · ')[0] : (online.name || online.id)}
                                </div>
                                {online.host_info && online.host_info.includes(' · ') && (
                                  <div style={{color:'#64748b', fontSize:12, marginTop:1}}>
                                    {online.host_info.split(' · ').slice(1).join(' · ')}
                                  </div>
                                )}
                              </div>
                            </div>
                          ) : (
                            <span style={{color:'#334155', fontSize:13}}>—</span>
                          )}
                        </td>
                        <td style={{padding:'14px 20px', fontFamily:'monospace', color:'#94a3b8', fontSize:13}}>
                          {editId === tk.device_id ? (
                            <input
                              value={editSecret} onChange={e => setEditSecret(e.target.value)}
                              placeholder={t('secret_label')}
                              autoFocus
                              style={{...inputStyle, width:240}}
                            />
                          ) : tk.secret}
                        </td>
                        <td style={{padding:'14px 20px'}}>
                          <div style={{display:'flex', gap:8}}>
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
                    )})}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function AgentsTable({ agents }: { agents: AgentInfo[] }) {
  const { t } = useI18n()
  const border = 'rgba(255,255,255,0.06)'
  const textMuted = '#64748b'
  const surface2 = '#141d35'

  const platformIcon = (p: string) => {
    if (p.includes('darwin') || p.includes('mac')) return (
      <svg viewBox="0 0 24 24" fill="currentColor" style={{width:15,height:15,verticalAlign:'middle',marginRight:6}}>
        <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.54 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/>
      </svg>
    )
    if (p.includes('windows')) return (
      <svg viewBox="0 0 24 24" style={{width:15,height:15,verticalAlign:'middle',marginRight:6}}>
        <path fill="#F25022" d="M1 1h10v10H1z"/>
        <path fill="#7FBA00" d="M13 1h10v10H13z"/>
        <path fill="#00A4EF" d="M1 13h10v10H1z"/>
        <path fill="#FFB900" d="M13 13h10v10H13z"/>
      </svg>
    )
    return <span style={{marginRight:6}}>🐧</span>
  }

  return (
    <div style={{ background:surface2, border:`1px solid ${border}`, borderRadius:16, overflow:'hidden' }}>
      <table style={{width:'100%', borderCollapse:'collapse'}}>
        <thead>
          <tr style={{borderBottom:`1px solid ${border}`}}>
            {[t('device_id_col'), t('host_info'), t('viewers')].map(h => (
              <th key={h} style={{padding:'14px 20px', textAlign:'left', color:textMuted, fontSize:13, fontWeight:600}}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {agents.length === 0 && (
            <tr><td colSpan={3} style={{padding:40, textAlign:'center', color:textMuted}}>{t('no_agents')}</td></tr>
          )}
          {agents.map(a => (
            <tr key={a.id} style={{borderBottom:`1px solid rgba(255,255,255,0.03)`}}>
              <td style={{padding:'14px 20px', fontFamily:'monospace', color:'#a5b4fc'}}>{a.id}</td>
              <td style={{padding:'14px 20px'}}>
                <div style={{display:'flex', alignItems:'center', gap:8}}>
                  {platformIcon(a.platform)}
                  <div>
                    <div style={{color:'#e2e8f0', fontSize:13, fontWeight:500}}>
                      {a.host_info ? a.host_info.split(' · ')[0] : (a.name || a.id)}
                    </div>
                    {a.host_info && a.host_info.includes(' · ') && (
                      <div style={{color:'#64748b', fontSize:12, marginTop:2}}>
                        {a.host_info.split(' · ').slice(1).join(' · ')}
                      </div>
                    )}
                  </div>
                </div>
              </td>
              <td style={{padding:'14px 20px'}}>
                <span style={{
                  background: a.viewer_count > 0 ? 'rgba(34,197,94,0.12)' : 'rgba(100,116,139,0.12)',
                  color: a.viewer_count > 0 ? '#4ade80' : '#64748b',
                  borderRadius:100, padding:'4px 12px', fontSize:13, fontWeight:500,
                }}>
                  {a.viewer_count > 0 ? a.viewer_count : '—'}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

const inputStyle: React.CSSProperties = {
  background: 'rgba(255,255,255,0.05)',
  border: '1px solid rgba(255,255,255,0.08)',
  borderRadius: 8, padding: '10px 14px',
  color: '#e2e8f0', fontSize: 14, outline: 'none',
  flex: '1 1 160px', minWidth: 0,
}

const btnSmallBlue: React.CSSProperties = {
  background:'rgba(99,102,241,0.12)', border:'1px solid rgba(99,102,241,0.2)',
  color:'#a5b4fc', borderRadius:6, padding:'6px 12px', fontSize:12,
  cursor:'pointer', fontWeight:500,
}
const btnSmallRed: React.CSSProperties = {
  background:'rgba(248,113,113,0.08)', border:'1px solid rgba(248,113,113,0.15)',
  color:'#f87171', borderRadius:6, padding:'6px 12px', fontSize:12,
  cursor:'pointer', fontWeight:500,
}
const btnSmallGreen: React.CSSProperties = {
  background:'rgba(34,197,94,0.1)', border:'1px solid rgba(34,197,94,0.2)',
  color:'#4ade80', borderRadius:6, padding:'6px 12px', fontSize:12,
  cursor:'pointer', fontWeight:500,
}
const btnSmallGray: React.CSSProperties = {
  background:'rgba(100,116,139,0.1)', border:'1px solid rgba(100,116,139,0.15)',
  color:'#64748b', borderRadius:6, padding:'6px 12px', fontSize:12,
  cursor:'pointer', fontWeight:500,
}
