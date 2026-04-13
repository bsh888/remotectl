import { useState, useEffect, useCallback } from 'react'

interface AgentInfo {
  id: string
  name: string
  platform: string
  viewer_count: number
}

interface TokenInfo {
  device_id: string
  secret: string
}

type AdminView = 'dashboard' | 'agents' | 'tokens'

const API = (path: string) => path

function apiFetch(path: string, token: string, opts?: RequestInit) {
  return fetch(API(path), {
    ...opts,
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(opts?.headers || {}),
    },
  })
}

export default function AdminPage() {
  const [token, setToken] = useState(() => sessionStorage.getItem('admin_token') || '')
  const [loginPwd, setLoginPwd] = useState('')
  const [loginErr, setLoginErr] = useState('')
  const [loginLoading, setLoginLoading] = useState(false)
  const [view, setView] = useState<AdminView>('dashboard')
  const [agents, setAgents] = useState<AgentInfo[]>([])
  const [tokens, setTokens] = useState<TokenInfo[]>([])

  // Token form
  const [addDeviceId, setAddDeviceId] = useState('')
  const [addSecret, setAddSecret] = useState('')
  const [addErr, setAddErr] = useState('')
  const [editId, setEditId] = useState<string | null>(null)
  const [editSecret, setEditSecret] = useState('')

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
        setLoginErr('密码错误')
      }
    } catch {
      setLoginErr('连接失败')
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
        setAddErr(d.error || '添加失败')
      }
    } catch { setAddErr('请求失败') }
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
    if (!confirm(`确认删除设备 ${deviceId} 的 token？`)) return
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
          }}>RemoteCtl 管理后台</div>
          <p style={{color:textMuted, fontSize:14, marginBottom:32}}>请输入管理员密码登录</p>
          <form onSubmit={handleLogin}>
            <input
              type="password"
              value={loginPwd}
              onChange={e => setLoginPwd(e.target.value)}
              placeholder="管理员密码"
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
              {loginLoading ? '登录中...' : '登录'}
            </button>
          </form>
        </div>
      </div>
    )
  }

  const sideItems: {key: AdminView; label: string; icon: string}[] = [
    { key: 'dashboard', label: '总览', icon: '📊' },
    { key: 'agents', label: '在线设备', icon: '🖥️' },
    { key: 'tokens', label: 'Token 管理', icon: '🔑' },
  ]

  return (
    <div style={{
      minHeight:'100vh', background:dark,
      fontFamily:'-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      color:'#e2e8f0', display:'flex', flexDirection:'column',
    }}>
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
        }}>RemoteCtl 管理后台</span>
        <button onClick={logout} style={{
          background:'rgba(248,113,113,0.1)', border:'1px solid rgba(248,113,113,0.2)',
          color:'#f87171', borderRadius:8, padding:'8px 16px',
          fontSize:13, cursor:'pointer',
        }}>退出登录</button>
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
                alignItems:'center', gap:10, fontSize:14, borderRadius:0,
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
              <h2 style={{margin:'0 0 8px', fontSize:24, fontWeight:700}}>总览</h2>
              <p style={{color:textMuted, marginBottom:32, fontSize:14}}>系统运行状态一览</p>
              <div style={{display:'grid', gridTemplateColumns:'repeat(auto-fit, minmax(200px,1fr))', gap:20}}>
                {[
                  { label:'在线设备', value: agents.length, color:'#6366f1', icon:'🖥️' },
                  { label:'Token 数量', value: tokens.length, color:'#8b5cf6', icon:'🔑' },
                  { label:'活跃连接', value: agents.reduce((s,a) => s+a.viewer_count, 0), color:'#06b6d4', icon:'👁️' },
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
                <div style={{marginTop:32}}>
                  <h3 style={{marginBottom:16, fontWeight:600}}>在线设备</h3>
                  <AgentsTable agents={agents} />
                </div>
              )}
            </div>
          )}

          {/* Agents */}
          {view === 'agents' && (
            <div>
              <h2 style={{margin:'0 0 8px', fontSize:24, fontWeight:700}}>在线设备</h2>
              <p style={{color:textMuted, marginBottom:32, fontSize:14}}>每 5 秒自动刷新</p>
              <AgentsTable agents={agents} />
            </div>
          )}

          {/* Tokens */}
          {view === 'tokens' && (
            <div>
              <h2 style={{margin:'0 0 8px', fontSize:24, fontWeight:700}}>Token 管理</h2>
              <p style={{color:textMuted, marginBottom:32, fontSize:14}}>管理各设备的认证 Token，修改后立即生效并持久化到配置文件</p>

              {/* Add form */}
              <div style={{
                background:surface2, border:`1px solid ${border}`,
                borderRadius:16, padding:24, marginBottom:24,
              }}>
                <h3 style={{margin:'0 0 16px', fontWeight:600, fontSize:16}}>添加设备 Token</h3>
                <form onSubmit={handleAddToken} style={{display:'flex', gap:12, flexWrap:'wrap' as const}}>
                  <input
                    value={addDeviceId} onChange={e => setAddDeviceId(e.target.value)}
                    placeholder="设备 ID（9位数字）"
                    style={inputStyle}
                  />
                  <input
                    value={addSecret} onChange={e => setAddSecret(e.target.value)}
                    placeholder="Token 密钥"
                    style={inputStyle}
                  />
                  <button type="submit" style={{
                    background:'linear-gradient(135deg,#6366f1,#8b5cf6)',
                    border:'none', borderRadius:8, padding:'10px 20px',
                    color:'white', fontWeight:600, cursor:'pointer', fontSize:14,
                    whiteSpace:'nowrap' as const,
                  }}>添加</button>
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
                      {['设备 ID', '设备信息', 'Token（已脱敏）', '操作'].map(h => (
                        <th key={h} style={{padding:'14px 20px', textAlign:'left', color:textMuted, fontSize:13, fontWeight:600}}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {tokens.length === 0 && (
                      <tr><td colSpan={4} style={{padding:40, textAlign:'center', color:textMuted}}>暂无 Token</td></tr>
                    )}
                    {tokens.map(t => {
                      const online = agents.find(a => a.id === t.device_id)
                      return (
                      <tr key={t.device_id} style={{borderBottom:`1px solid rgba(255,255,255,0.03)`}}>
                        <td style={{padding:'14px 20px', fontFamily:'monospace', color:'#a5b4fc'}}>{t.device_id}</td>
                        <td style={{padding:'14px 20px'}}>
                          {online ? (
                            <div style={{display:'flex', alignItems:'center', gap:8}}>
                              <span style={{
                                width:7, height:7, borderRadius:'50%',
                                background:'#4ade80', display:'inline-block', flexShrink:0,
                              }}/>
                              <span style={{color:'#e2e8f0', fontSize:13, fontWeight:500}}>{online.name || online.id}</span>
                              <span style={{color:'#64748b', fontSize:12}}>{online.platform}</span>
                            </div>
                          ) : (
                            <span style={{color:'#334155', fontSize:13}}>离线</span>
                          )}
                        </td>
                        <td style={{padding:'14px 20px', fontFamily:'monospace', color:'#94a3b8', fontSize:13}}>
                          {editId === t.device_id ? (
                            <input
                              value={editSecret} onChange={e => setEditSecret(e.target.value)}
                              placeholder="新 Token 密钥"
                              autoFocus
                              style={{...inputStyle, width:240}}
                            />
                          ) : t.secret}
                        </td>
                        <td style={{padding:'14px 20px'}}>
                          <div style={{display:'flex', gap:8}}>
                            {editId === t.device_id ? (
                              <>
                                <button onClick={() => handleUpdateToken(t.device_id)} style={btnSmallGreen}>保存</button>
                                <button onClick={() => setEditId(null)} style={btnSmallGray}>取消</button>
                              </>
                            ) : (
                              <>
                                <button onClick={() => { setEditId(t.device_id); setEditSecret('') }} style={btnSmallBlue}>修改</button>
                                <button onClick={() => handleDeleteToken(t.device_id)} style={btnSmallRed}>删除</button>
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
            {['设备 ID', '名称', '平台', '控制端数'].map(h => (
              <th key={h} style={{padding:'14px 20px', textAlign:'left', color:textMuted, fontSize:13, fontWeight:600}}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {agents.length === 0 && (
            <tr><td colSpan={4} style={{padding:40, textAlign:'center', color:textMuted}}>暂无在线设备</td></tr>
          )}
          {agents.map(a => (
            <tr key={a.id} style={{borderBottom:`1px solid rgba(255,255,255,0.03)`}}>
              <td style={{padding:'14px 20px', fontFamily:'monospace', color:'#a5b4fc'}}>{a.id}</td>
              <td style={{padding:'14px 20px', color:'#e2e8f0'}}>{a.name || '-'}</td>
              <td style={{padding:'14px 20px', color:'#94a3b8'}}>
                {platformIcon(a.platform)}{a.platform}
              </td>
              <td style={{padding:'14px 20px'}}>
                <span style={{
                  background: a.viewer_count > 0 ? 'rgba(34,197,94,0.12)' : 'rgba(100,116,139,0.12)',
                  color: a.viewer_count > 0 ? '#4ade80' : '#64748b',
                  borderRadius:100, padding:'4px 12px', fontSize:13, fontWeight:500,
                }}>
                  {a.viewer_count > 0 ? `${a.viewer_count} 个连接` : '空闲'}
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
