import { useState, useEffect, useRef, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { useI18n, LANG_NAMES, type Lang } from '../i18n'

interface VersionInfo { version: string }

const RELEASES_BASE = 'https://github.com/bsh888/remotectl-releases/releases/download'
const RELEASES_PAGE  = 'https://github.com/bsh888/remotectl-releases/releases'

// ── CSS var shorthands ─────────────────────────────────────────────────────────
const V = {
  bg:        'var(--bg)',
  surface:   'var(--surface)',
  surface2:  'var(--surface-2)',
  surface3:  'var(--surface-3)',
  border:    'var(--border)',
  border2:   'var(--border-2)',
  border3:   'var(--border-3)',
  accent:    'var(--accent)',
  accentDim: 'var(--accent-dim)',
  accentBdr: 'var(--accent-bdr)',
  green:     'var(--green)',
  greenDim:  'var(--green-dim)',
  text1:     'var(--text-1)',
  text2:     'var(--text-2)',
  text3:     'var(--text-3)',
  mono:      'var(--mono)',
  sans:      'var(--sans)',
  display:   'var(--display)',
}

// ── Grid background pattern ────────────────────────────────────────────────────
const gridBg = `
  linear-gradient(var(--border) 1px, transparent 1px),
  linear-gradient(90deg, var(--border) 1px, transparent 1px)
`

// ── Feature definitions ────────────────────────────────────────────────────────
const features = [
  { num: '01', titleKey: 'feat_h264_title',    descKey: 'feat_h264_desc' },
  { num: '02', titleKey: 'feat_webrtc_title',  descKey: 'feat_webrtc_desc' },
  { num: '03', titleKey: 'feat_e2ee_title',    descKey: 'feat_e2ee_desc' },
  { num: '04', titleKey: 'feat_cross_title',   descKey: 'feat_cross_desc' },
  { num: '05', titleKey: 'feat_latency_title', descKey: 'feat_latency_desc' },
  { num: '06', titleKey: 'feat_chat_title',    descKey: 'feat_chat_desc' },
]

const platforms: { nameKey: string; icon: ReactNode; label: string; ext: string }[] = [
  { nameKey: 'app_macos',   icon: <AppleIcon />,   label: 'remotectl-app-macos',           ext: 'zip'    },
  { nameKey: 'app_windows', icon: <WinIcon />,     label: 'remotectl-app-windows-amd64',   ext: 'zip'    },
  { nameKey: 'app_linux',   icon: '🐧',             label: 'remotectl-app-linux-amd64',     ext: 'tar.gz' },
  { nameKey: 'agent_linux', icon: '⚙️',             label: 'remotectl-agent-linux-amd64',   ext: 'tar.gz' },
]

function AppleIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" style={{width:20,height:20}}>
      <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.54 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zm3.378-3.066c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701z"/>
    </svg>
  )
}
function WinIcon() {
  return (
    <svg viewBox="0 0 24 24" style={{width:20,height:20}}>
      <path fill="#F25022" d="M1 1h10v10H1z"/>
      <path fill="#7FBA00" d="M13 1h10v10H13z"/>
      <path fill="#00A4EF" d="M1 13h10v10H1z"/>
      <path fill="#FFB900" d="M13 13h10v10H13z"/>
    </svg>
  )
}

// ── Connection diagram (hero visual) ──────────────────────────────────────────
function ConnectionDiagram() {
  return (
    <div style={{
      position: 'relative',
      width: 340,
      height: 160,
      flexShrink: 0,
    }}>
      {/* Left device */}
      <div style={{
        position: 'absolute',
        left: 0, top: '50%', transform: 'translateY(-50%)',
        width: 120, padding: '14px 16px',
        background: V.surface2,
        border: `1px solid ${V.border2}`,
        borderRadius: 4,
        animation: 'rc-slide-r 0.6s 0.3s both',
      }}>
        <div style={{fontFamily:V.mono, fontSize:9, color:V.text3, letterSpacing:'0.08em', marginBottom:6}}>LOCAL</div>
        <div style={{fontFamily:V.mono, fontSize:11, color:V.text1, letterSpacing:'0.05em'}}>192.168.1.x</div>
        <div style={{display:'flex', alignItems:'center', gap:5, marginTop:8}}>
          <div style={{
            width:6, height:6, borderRadius:'50%', background:V.green,
            animation:'rc-pulse-dot 2s infinite',
          }}/>
          <span style={{fontFamily:V.mono, fontSize:9, color:V.green}}>READY</span>
        </div>
      </div>

      {/* SVG connection line */}
      <svg style={{position:'absolute', left:120, top:0, width:'calc(100% - 240px)', height:'100%', overflow:'visible'}}
           viewBox="0 0 100 160" preserveAspectRatio="none">
        <line x1="0" y1="80" x2="100" y2="80"
          stroke="var(--border-2)" strokeWidth="1" strokeDasharray="4 3"/>
        <line x1="0" y1="80" x2="100" y2="80"
          stroke="var(--accent)" strokeWidth="1.5"
          strokeDasharray="12 188"
          style={{animation:'rc-travel 2.5s linear infinite'}}/>
      </svg>

      {/* P2P badge */}
      <div style={{
        position: 'absolute',
        left: '50%', top: '50%',
        transform: 'translate(-50%, -50%)',
        background: V.surface,
        border: `1px solid ${V.accentBdr}`,
        borderRadius: 2,
        padding: '3px 7px',
        fontFamily: V.mono,
        fontSize: 8,
        color: V.accent,
        letterSpacing: '0.12em',
        whiteSpace: 'nowrap',
        zIndex: 2,
      }}>P2P</div>

      {/* Right device */}
      <div style={{
        position: 'absolute',
        right: 0, top: '50%', transform: 'translateY(-50%)',
        width: 120, padding: '14px 16px',
        background: V.surface2,
        border: `1px solid ${V.border2}`,
        borderRadius: 4,
        animation: 'rc-slide-l 0.6s 0.3s both',
      }}>
        <div style={{fontFamily:V.mono, fontSize:9, color:V.text3, letterSpacing:'0.08em', marginBottom:6}}>REMOTE</div>
        <div style={{fontFamily:V.mono, fontSize:11, color:V.text1, letterSpacing:'0.05em'}}>987654321</div>
        <div style={{display:'flex', alignItems:'center', gap:5, marginTop:8}}>
          <div style={{width:6, height:6, borderRadius:'50%', background:V.accent}}/>
          <span style={{fontFamily:V.mono, fontSize:9, color:V.accent}}>CTRL</span>
        </div>
      </div>
    </div>
  )
}

// ── Responsive hook ────────────────────────────────────────────────────────────
function useIsMobile(breakpoint = 640) {
  const [isMobile, setIsMobile] = useState(() => window.innerWidth < breakpoint)
  useEffect(() => {
    const fn = () => setIsMobile(window.innerWidth < breakpoint)
    window.addEventListener('resize', fn)
    return () => window.removeEventListener('resize', fn)
  }, [breakpoint])
  return isMobile
}

// ── Main component ─────────────────────────────────────────────────────────────
export default function LandingPage() {
  const navigate = useNavigate()
  const { t, lang, setLang } = useI18n()
  const [version, setVersion] = useState('')
  const [scrolled, setScrolled] = useState(false)
  const [showLang, setShowLang] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const langRef = useRef<HTMLDivElement>(null)
  const isMobile = useIsMobile()
  const px = isMobile ? '16px' : '28px'

  useEffect(() => {
    fetch('/api/version').then(r => r.json()).then((d: VersionInfo) => setVersion(d.version || '')).catch(() => {})
  }, [])

  useEffect(() => {
    const fn = () => setScrolled(window.scrollY > 10)
    window.addEventListener('scroll', fn)
    return () => window.removeEventListener('scroll', fn)
  }, [])

  useEffect(() => {
    const fn = (e: MouseEvent) => {
      if (langRef.current && !langRef.current.contains(e.target as Node)) setShowLang(false)
    }
    document.addEventListener('mousedown', fn)
    return () => document.removeEventListener('mousedown', fn)
  }, [])

  const dlUrl = (p: typeof platforms[0]) =>
    version ? `${RELEASES_BASE}/${version}/${p.label}-${version}.${p.ext}` : RELEASES_PAGE

  // ── Nav ──────────────────────────────────────────────────────────────────────
  return (
    <div style={{ fontFamily: V.sans, color: V.text1, minHeight: '100vh', background: V.bg }}>

      <nav style={{
        position: 'fixed', top:0, left:0, right:0, zIndex:100,
        borderBottom: `1px solid ${scrolled || menuOpen ? V.border2 : 'transparent'}`,
        background: scrolled || menuOpen ? 'rgba(7,10,15,0.96)' : 'transparent',
        backdropFilter: scrolled || menuOpen ? 'blur(16px)' : 'none',
        transition: 'all 0.25s',
      }}>
        {/* Main nav row */}
        <div style={{
          height: 56,
          maxWidth:1200, margin:'0 auto', padding:`0 ${px}`,
          width:'100%', display:'flex', alignItems:'center', justifyContent:'space-between',
        }}>
          {/* Logo */}
          <div style={{ display:'flex', alignItems:'center', gap:10 }}>
            <div style={{
              width:28, height:28, borderRadius:3,
              background: V.accent,
              display:'flex', alignItems:'center', justifyContent:'center',
              flexShrink: 0,
            }}>
              <svg viewBox="0 0 16 16" fill="none" style={{width:14,height:14}}>
                <rect x="1" y="2" width="14" height="10" rx="1.5" stroke="white" strokeWidth="1.5"/>
                <path d="M5 15h6M8 12v3" stroke="white" strokeWidth="1.5" strokeLinecap="round"/>
              </svg>
            </div>
            <span style={{fontFamily:V.display, fontSize:15, fontWeight:700, letterSpacing:'-0.02em', color:V.text1}}>
              RemoteCtl
            </span>
          </div>

          {/* Desktop links */}
          {!isMobile && (
            <div style={{display:'flex', alignItems:'center', gap:4}}>
              {[
                ['#features', t('nav_features')],
                ['#download', t('nav_download')],
              ].map(([href, label]) => (
                <a key={href} href={href} style={{
                  color:V.text2, textDecoration:'none', fontSize:13,
                  padding:'6px 14px', borderRadius:3,
                  transition:'color 0.15s',
                }}
                onMouseEnter={e => (e.currentTarget.style.color = V.text1)}
                onMouseLeave={e => (e.currentTarget.style.color = V.text2)}
                >{label}</a>
              ))}

              <button onClick={() => navigate('/admin')} style={{
                background:'transparent', border:`1px solid ${V.border2}`,
                color:V.text2, borderRadius:3, padding:'5px 14px', fontSize:13,
                cursor:'pointer', transition:'all 0.15s',
              }}
              onMouseEnter={e => { e.currentTarget.style.borderColor=V.border3; e.currentTarget.style.color=V.text1 }}
              onMouseLeave={e => { e.currentTarget.style.borderColor=V.border2; e.currentTarget.style.color=V.text2 }}
              >{t('nav_admin')}</button>

              {/* Language switcher */}
              <div ref={langRef} style={{position:'relative', marginLeft:4}}>
                <button onClick={() => setShowLang(v => !v)} style={{
                  background:'transparent', border:`1px solid ${V.border2}`,
                  color:V.text3, borderRadius:3, padding:'5px 10px', fontSize:12,
                  cursor:'pointer', fontFamily:V.mono, letterSpacing:'0.04em',
                  transition:'all 0.15s',
                }}
                onMouseEnter={e => { e.currentTarget.style.color=V.text2; e.currentTarget.style.borderColor=V.border3 }}
                onMouseLeave={e => { e.currentTarget.style.color=V.text3; e.currentTarget.style.borderColor=V.border2 }}
                >
                  {lang.toUpperCase().replace('_','/')}
                </button>
                {showLang && (
                  <div style={{
                    position:'absolute', top:'calc(100% + 6px)', right:0,
                    background:V.surface, border:`1px solid ${V.border2}`,
                    borderRadius:4, overflow:'hidden', minWidth:130, zIndex:200,
                    boxShadow:'0 8px 24px rgba(0,0,0,0.4)',
                  }}>
                    {(['zh','en','zh_TW'] as Lang[]).map(l => (
                      <button key={l} onClick={() => { setLang(l); setShowLang(false) }} style={{
                        padding:'9px 16px', fontSize:13, cursor:'pointer',
                        color: l === lang ? V.accent : V.text2,
                        fontWeight: l === lang ? 600 : 400,
                        background: l === lang ? V.accentDim : 'transparent',
                        border:'none', width:'100%', textAlign:'left',
                        fontFamily: V.sans,
                        transition:'background 0.1s',
                      }}
                      onMouseEnter={e => { if (l !== lang) e.currentTarget.style.background = V.surface2 }}
                      onMouseLeave={e => { if (l !== lang) e.currentTarget.style.background = 'transparent' }}
                      >{LANG_NAMES[l]}</button>
                    ))}
                  </div>
                )}
              </div>

              {/* CTA */}
              <button onClick={() => navigate('/control')} style={{
                marginLeft:8,
                background:V.accent, border:'none', borderRadius:3,
                color:'white', padding:'7px 18px', fontSize:13, fontWeight:600,
                cursor:'pointer', transition:'opacity 0.15s',
                letterSpacing:'-0.01em',
              }}
              onMouseEnter={e => (e.currentTarget.style.opacity = '0.88')}
              onMouseLeave={e => (e.currentTarget.style.opacity = '1')}
              >{t('nav_connect')}</button>
            </div>
          )}

          {/* Mobile right: lang + connect + hamburger */}
          {isMobile && (
            <div style={{display:'flex', alignItems:'center', gap:8}}>
              {/* Language switcher */}
              <div ref={langRef} style={{position:'relative'}}>
                <button onClick={() => setShowLang(v => !v)} style={{
                  background:'transparent', border:`1px solid ${V.border2}`,
                  color:V.text3, borderRadius:3, padding:'5px 8px', fontSize:11,
                  cursor:'pointer', fontFamily:V.mono, letterSpacing:'0.04em',
                }}>
                  {lang.toUpperCase().replace('_','/')}
                </button>
                {showLang && (
                  <div style={{
                    position:'absolute', top:'calc(100% + 6px)', right:0,
                    background:V.surface, border:`1px solid ${V.border2}`,
                    borderRadius:4, overflow:'hidden', minWidth:130, zIndex:200,
                    boxShadow:'0 8px 24px rgba(0,0,0,0.4)',
                  }}>
                    {(['zh','en','zh_TW'] as Lang[]).map(l => (
                      <button key={l} onClick={() => { setLang(l); setShowLang(false) }} style={{
                        padding:'9px 16px', fontSize:13, cursor:'pointer',
                        color: l === lang ? V.accent : V.text2,
                        fontWeight: l === lang ? 600 : 400,
                        background: l === lang ? V.accentDim : 'transparent',
                        border:'none', width:'100%', textAlign:'left',
                        fontFamily: V.sans,
                      }}>{LANG_NAMES[l]}</button>
                    ))}
                  </div>
                )}
              </div>

              <button onClick={() => navigate('/control')} style={{
                background:V.accent, border:'none', borderRadius:3,
                color:'white', padding:'6px 14px', fontSize:12, fontWeight:600,
                cursor:'pointer', letterSpacing:'-0.01em',
              }}>{t('nav_connect')}</button>

              {/* Hamburger */}
              <button onClick={() => setMenuOpen(v => !v)} style={{
                background:'transparent', border:`1px solid ${V.border2}`,
                color:V.text2, borderRadius:3, padding:'6px 8px',
                cursor:'pointer', lineHeight:1, fontSize:16,
              }}>
                {menuOpen ? '✕' : '☰'}
              </button>
            </div>
          )}
        </div>

        {/* Mobile dropdown menu */}
        {isMobile && menuOpen && (
          <div style={{
            borderTop:`1px solid ${V.border2}`,
            padding:'8px 0 12px',
          }}>
            {[
              ['#features', t('nav_features')],
              ['#download', t('nav_download')],
            ].map(([href, label]) => (
              <a key={href} href={href} onClick={() => setMenuOpen(false)} style={{
                display:'block', padding:'12px 16px',
                color:V.text2, textDecoration:'none', fontSize:14,
              }}>{label}</a>
            ))}
            <button onClick={() => { navigate('/admin'); setMenuOpen(false) }} style={{
              display:'block', width:'100%', textAlign:'left',
              padding:'12px 16px', background:'transparent', border:'none',
              color:V.text2, fontSize:14, cursor:'pointer',
            }}>{t('nav_admin')}</button>
          </div>
        )}
      </nav>

      {/* ── Hero ─────────────────────────────────────────────────────────────── */}
      <section style={{
        minHeight: '100vh',
        display: 'flex', alignItems: 'center',
        backgroundImage: gridBg,
        backgroundSize: '48px 48px',
        position: 'relative',
        overflow: 'hidden',
      }}>
        {/* Radial vignette */}
        <div style={{
          position:'absolute', inset:0, pointerEvents:'none',
          background:'radial-gradient(ellipse 80% 60% at 50% 50%, transparent 30%, var(--bg) 100%)',
        }}/>
        {/* Orange glow bottom-left */}
        <div style={{
          position:'absolute', bottom:-120, left:-80,
          width:500, height:500, borderRadius:'50%', pointerEvents:'none',
          background:'radial-gradient(circle, rgba(255,80,51,0.06) 0%, transparent 70%)',
        }}/>

        <div style={{
          maxWidth:1200, margin:'0 auto',
          padding: isMobile ? '96px 16px 64px' : '120px 28px 80px',
          width:'100%', position:'relative', zIndex:1,
          display:'flex', alignItems:'center',
          justifyContent: isMobile ? 'center' : 'space-between',
          gap:48, flexWrap:'wrap',
        }}>
          {/* Text block */}
          <div style={{ maxWidth: isMobile ? '100%' : 560 }}>
            {/* Tag */}
            <div style={{
              display:'inline-flex', alignItems:'center', gap:8,
              border:`1px solid ${V.accentBdr}`,
              borderRadius:2, padding:'5px 12px',
              marginBottom:28,
              animation:'rc-fade-up 0.5s 0.1s both',
            }}>
              <div style={{width:5,height:5,borderRadius:'50%',background:V.accent}}/>
              <span style={{fontFamily:V.mono, fontSize:10, color:V.accent, letterSpacing:'0.12em'}}>
                WebRTC · P2P · E2EE
              </span>
            </div>

            {/* Title */}
            <h1 style={{
              fontFamily: V.display,
              fontSize: isMobile ? 'clamp(44px,14vw,72px)' : 'clamp(48px,7vw,76px)',
              fontWeight: 800,
              lineHeight: 1.05,
              letterSpacing: '-0.035em',
              marginBottom: 24,
              animation: 'rc-fade-up 0.5s 0.2s both',
            }}>
              <span style={{color:V.text1}}>Remote</span>
              <br/>
              <span style={{color:V.accent}}>Desktop</span>
              <br/>
              <span style={{color:V.text1}}>Control</span>
            </h1>

            {/* Subtitle */}
            <p style={{
              fontSize: isMobile ? 15 : 16,
              color:V.text2, lineHeight:1.75, marginBottom:40,
              maxWidth:440,
              animation:'rc-fade-up 0.5s 0.3s both',
            }}>
              {t('hero_subtitle')}
            </p>

            {/* CTAs */}
            <div style={{
              display:'flex', gap:12, flexWrap:'wrap',
              animation:'rc-fade-up 0.5s 0.4s both',
            }}>
              <button onClick={() => navigate('/control')} style={{
                background:V.accent, border:'none', borderRadius:3,
                color:'white',
                padding: isMobile ? '11px 22px' : '13px 28px',
                fontSize: isMobile ? 14 : 15,
                fontWeight:600,
                cursor:'pointer', letterSpacing:'-0.01em',
                transition:'opacity 0.15s, transform 0.15s',
              }}
              onMouseEnter={e => { e.currentTarget.style.opacity='0.9'; e.currentTarget.style.transform='translateY(-1px)' }}
              onMouseLeave={e => { e.currentTarget.style.opacity='1'; e.currentTarget.style.transform='translateY(0)' }}
              >{t('hero_start')} →</button>

              <a href="#download" style={{
                background:'transparent', border:`1px solid ${V.border2}`,
                borderRadius:3, color:V.text1,
                padding: isMobile ? '11px 22px' : '13px 28px',
                fontSize: isMobile ? 14 : 15,
                fontWeight:500, textDecoration:'none', cursor:'pointer',
                transition:'border-color 0.15s',
              }}
              onMouseEnter={e => (e.currentTarget.style.borderColor = V.border3)}
              onMouseLeave={e => (e.currentTarget.style.borderColor = V.border2)}
              >{t('hero_download')}</a>
            </div>

            {/* Stats row */}
            <div style={{
              display:'flex', gap: isMobile ? 20 : 32, marginTop:48,
              paddingTop:32, borderTop:`1px solid ${V.border}`,
              animation:'rc-fade-up 0.5s 0.5s both',
            }}>
              {[
                ['H.264', 'Hardware Enc.'],
                ['P2P', 'Direct Connect'],
                ['E2EE', 'Input Encrypted'],
              ].map(([val, lbl]) => (
                <div key={val}>
                  <div style={{fontFamily:V.mono, fontSize:14, color:V.accent, fontWeight:600, letterSpacing:'0.04em'}}>{val}</div>
                  <div style={{fontSize:11, color:V.text3, marginTop:3, letterSpacing:'0.04em'}}>{lbl}</div>
                </div>
              ))}
            </div>
          </div>

          {/* Diagram — hidden on mobile to avoid overflow */}
          {!isMobile && (
            <div style={{animation:'rc-fade-in 0.8s 0.5s both'}}>
              <ConnectionDiagram />
            </div>
          )}
        </div>
      </section>

      {/* ── Features ───────────────────────────────────────────────────────── */}
      <section id="features" style={{
        maxWidth:1200, margin:'0 auto', padding:`80px ${px}`,
      }}>
        {/* Section header */}
        <div style={{display:'flex', alignItems:'baseline', gap:16, marginBottom:48}}>
          <h2 style={{
            fontFamily:V.display, fontSize: isMobile ? 26 : 32, fontWeight:800,
            letterSpacing:'-0.03em', color:V.text1,
          }}>{t('nav_features')}</h2>
          <div style={{flex:1, height:1, background:V.border}}/>
          {!isMobile && (
            <span style={{fontFamily:V.mono, fontSize:10, color:V.text3, letterSpacing:'0.1em'}}>
              06 MODULES
            </span>
          )}
        </div>

        <div style={{
          display:'grid',
          gridTemplateColumns: isMobile ? '1fr' : 'repeat(auto-fill, minmax(340px, 1fr))',
          gap:1,
          background:V.border2,
          border:`1px solid ${V.border2}`,
          borderRadius:4,
          overflow:'hidden',
        }}>
          {features.map(f => (
            <div key={f.num} style={{
              background:V.surface,
              padding: isMobile ? '20px 16px' : '28px 28px 28px 24px',
              transition:'background 0.15s',
              position:'relative',
            }}
            onMouseEnter={e => (e.currentTarget.style.background = V.surface2)}
            onMouseLeave={e => (e.currentTarget.style.background = V.surface)}
            >
              <div style={{
                fontFamily:V.mono, fontSize:10, color:V.accent,
                letterSpacing:'0.1em', marginBottom:14,
              }}>{f.num}</div>
              <div style={{
                fontFamily:V.display, fontSize:16, fontWeight:700,
                color:V.text1, marginBottom:10, letterSpacing:'-0.01em',
              }}>{t(f.titleKey)}</div>
              <div style={{fontSize:13, color:V.text2, lineHeight:1.7}}>{t(f.descKey)}</div>
            </div>
          ))}
        </div>
      </section>

      {/* ── Downloads ──────────────────────────────────────────────────────── */}
      <section id="download" style={{
        maxWidth:1200, margin:'0 auto', padding:`0 ${px} 80px`,
      }}>
        <div style={{display:'flex', alignItems:'baseline', gap:16, marginBottom:48}}>
          <h2 style={{
            fontFamily:V.display, fontSize: isMobile ? 26 : 32, fontWeight:800,
            letterSpacing:'-0.03em',
          }}>{t('dl_title')}</h2>
          <div style={{flex:1, height:1, background:V.border}}/>
          {version && (
            <span style={{
              fontFamily:V.mono, fontSize:10, color:V.green,
              letterSpacing:'0.1em', padding:'3px 8px',
              border:`1px solid ${V.greenDim}`, borderRadius:2,
              whiteSpace:'nowrap',
            }}>{version}</span>
          )}
        </div>

        <div style={{
          border:`1px solid ${V.border2}`, borderRadius:4, overflow:'hidden',
        }}>
          {/* Table header */}
          <div style={{
            display:'grid',
            gridTemplateColumns: isMobile ? '1fr auto' : '1fr 2fr auto',
            padding: isMobile ? '10px 16px' : '10px 24px',
            background:V.surface,
            borderBottom:`1px solid ${V.border2}`,
          }}>
            {(isMobile ? [t('platform'), ''] : [t('platform'), t('file'), '']).map((h, i) => (
              <div key={i} style={{
                fontFamily:V.mono, fontSize:10, color:V.text3,
                letterSpacing:'0.1em',
                textAlign: (isMobile ? i === 1 : i === 2) ? 'right' as const : 'left' as const,
              }}>{h}</div>
            ))}
          </div>

          {/* Platform rows */}
          {platforms.map((p, i) => (
            <div key={p.nameKey} style={{
              display:'grid',
              gridTemplateColumns: isMobile ? '1fr auto' : '1fr 2fr auto',
              padding: isMobile ? '14px 16px' : '16px 24px',
              alignItems:'center',
              borderBottom: i < platforms.length - 1 ? `1px solid ${V.border}` : 'none',
              background: V.bg,
              transition:'background 0.12s',
            }}
            onMouseEnter={e => (e.currentTarget.style.background = V.surface)}
            onMouseLeave={e => (e.currentTarget.style.background = V.bg)}
            >
              <div style={{display:'flex', alignItems:'center', gap:10, color:V.text1, fontSize:13, fontWeight:500}}>
                <span style={{color:V.text2}}>{p.icon}</span>
                {t(p.nameKey)}
              </div>
              {/* Filename — hidden on mobile */}
              {!isMobile && (
                <div style={{fontFamily:V.mono, fontSize:11, color:V.text3, letterSpacing:'0.04em'}}>
                  {p.label}-{version || 'vX.Y.Z'}.{p.ext}
                </div>
              )}
              <a href={dlUrl(p)} target="_blank" rel="noopener noreferrer" style={{
                fontFamily:V.mono, fontSize:11, color:V.accent, textDecoration:'none',
                border:`1px solid ${V.accentBdr}`, borderRadius:2,
                padding: isMobile ? '5px 10px' : '5px 14px',
                letterSpacing:'0.06em', transition:'all 0.15s',
                display:'inline-block', whiteSpace:'nowrap',
              }}
              onMouseEnter={e => { e.currentTarget.style.background=V.accentDim }}
              onMouseLeave={e => { e.currentTarget.style.background='transparent' }}
              >↓ {version || t('dl_github')}</a>
            </div>
          ))}
        </div>

        <div style={{marginTop:16, display:'flex', justifyContent:'flex-end'}}>
          <a href={RELEASES_PAGE} target="_blank" rel="noopener noreferrer" style={{
            fontFamily:V.mono, fontSize:11, color:V.text3,
            textDecoration:'none', letterSpacing:'0.06em',
            transition:'color 0.15s',
          }}
          onMouseEnter={e => (e.currentTarget.style.color = V.text2)}
          onMouseLeave={e => (e.currentTarget.style.color = V.text3)}
          >{t('dl_github')} ↗</a>
        </div>
      </section>

      {/* ── Footer ─────────────────────────────────────────────────────────── */}
      <footer style={{
        borderTop:`1px solid ${V.border}`,
        padding: isMobile ? '20px 16px' : '28px',
        display:'flex', alignItems:'center', justifyContent:'space-between',
        flexWrap:'wrap', gap:12,
      }}>
        <div style={{display:'flex', alignItems:'center', gap:8}}>
          <div style={{width:16,height:16,borderRadius:2,background:V.accent,opacity:0.9}}/>
          <span style={{fontFamily:V.mono, fontSize:11, color:V.text3, letterSpacing:'0.06em'}}>
            REMOTECTL · WebRTC · © 2025
          </span>
        </div>
        <div style={{fontFamily:V.mono, fontSize:10, color:V.text3, letterSpacing:'0.06em'}}>
          {version || '—'}
        </div>
      </footer>
    </div>
  )
}
