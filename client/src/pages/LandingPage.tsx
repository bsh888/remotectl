import { useState, useEffect, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { useI18n, LANG_NAMES, type Lang } from '../i18n'

interface VersionInfo {
  version: string
}

const RELEASES_BASE = 'https://github.com/bsh888/remotectl-releases/releases/download'
const RELEASES_PAGE = 'https://github.com/bsh888/remotectl-releases/releases'

const featureKeys = [
  { titleKey: 'feat_h264_title', descKey: 'feat_h264_desc', icon: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
      <path d="M15 10l4.553-2.069A1 1 0 0121 8.868V15.132a1 1 0 01-1.447.9L15 14M3 8a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V8z"/>
    </svg>
  )},
  { titleKey: 'feat_webrtc_title', descKey: 'feat_webrtc_desc', icon: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
      <circle cx="12" cy="12" r="3"/>
      <path d="M12 2v3M12 19v3M4.22 4.22l2.12 2.12M17.66 17.66l2.12 2.12M2 12h3M19 12h3M4.22 19.78l2.12-2.12M17.66 6.34l2.12-2.12"/>
    </svg>
  )},
  { titleKey: 'feat_e2ee_title', descKey: 'feat_e2ee_desc', icon: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
      <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
      <path d="M7 11V7a5 5 0 0110 0v4"/>
    </svg>
  )},
  { titleKey: 'feat_cross_title', descKey: 'feat_cross_desc', icon: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
      <rect x="2" y="3" width="20" height="14" rx="2"/>
      <path d="M8 21h8M12 17v4"/>
    </svg>
  )},
  { titleKey: 'feat_latency_title', descKey: 'feat_latency_desc', icon: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
      <path d="M13 10V3L4 14h7v7l9-11h-7z"/>
    </svg>
  )},
  { titleKey: 'feat_chat_title', descKey: 'feat_chat_desc', icon: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
      <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/>
    </svg>
  )},
]

const AppleLogo = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" style={{width:36,height:36}}>
    <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.54 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/>
  </svg>
)

const WindowsLogo = () => (
  <svg viewBox="0 0 24 24" style={{width:38,height:38}}>
    <path fill="#F25022" d="M1 1h10v10H1z"/>
    <path fill="#7FBA00" d="M13 1h10v10H13z"/>
    <path fill="#00A4EF" d="M1 13h10v10H1z"/>
    <path fill="#FFB900" d="M13 13h10v10H13z"/>
  </svg>
)

const platforms: { nameKey: string; icon: ReactNode; fileKey: string; ext: string; label: string }[] = [
  { nameKey: 'app_macos', icon: <AppleLogo />, fileKey: 'macos', ext: 'zip', label: 'remotectl-app-macos' },
  { nameKey: 'app_windows', icon: <WindowsLogo />, fileKey: 'windows', ext: 'zip', label: 'remotectl-app-windows-amd64' },
  { nameKey: 'app_linux', icon: '🐧', fileKey: 'linux', ext: 'tar.gz', label: 'remotectl-app-linux-amd64' },
  { nameKey: 'agent_linux', icon: '⚙️', fileKey: 'agent', ext: 'tar.gz', label: 'remotectl-agent-linux-amd64' },
]

export default function LandingPage() {
  const navigate = useNavigate()
  const { t, lang, setLang } = useI18n()
  const [version, setVersion] = useState<string>('')
  const [scrolled, setScrolled] = useState(false)
  const [showLang, setShowLang] = useState(false)

  useEffect(() => {
    fetch('/api/version')
      .then(r => r.json())
      .then((d: VersionInfo) => setVersion(d.version || ''))
      .catch(() => {})
  }, [])

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20)
    window.addEventListener('scroll', onScroll)
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  const downloadUrl = (p: typeof platforms[0]) => {
    if (!version) return RELEASES_PAGE
    return `${RELEASES_BASE}/${version}/${p.label}-${version}.${p.ext}`
  }

  // Styles
  const s = {
    root: {
      minHeight: '100vh',
      background: 'linear-gradient(135deg, #0a0e1a 0%, #0f1629 50%, #0a0e1a 100%)',
      color: '#e2e8f0',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      overflowX: 'hidden' as const,
    },
    nav: {
      position: 'fixed' as const,
      top: 0, left: 0, right: 0,
      zIndex: 100,
      transition: 'all 0.3s',
      background: scrolled ? 'rgba(10,14,26,0.95)' : 'transparent',
      backdropFilter: scrolled ? 'blur(12px)' : 'none',
      borderBottom: scrolled ? '1px solid rgba(99,102,241,0.15)' : '1px solid transparent',
    },
    navInner: {
      maxWidth: 1200,
      margin: '0 auto',
      padding: '0 24px',
      height: 64,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    logo: {
      fontSize: 22,
      fontWeight: 700,
      background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
      WebkitBackgroundClip: 'text' as const,
      WebkitTextFillColor: 'transparent' as const,
      letterSpacing: '-0.5px',
    },
    navLinks: {
      display: 'flex',
      gap: 32,
      listStyle: 'none',
      margin: 0,
      padding: 0,
      alignItems: 'center',
    },
    navLink: {
      color: '#94a3b8',
      textDecoration: 'none',
      fontSize: 14,
      cursor: 'pointer',
      transition: 'color 0.2s',
    },
    btnPrimary: {
      background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
      color: 'white',
      border: 'none',
      borderRadius: 8,
      padding: '10px 20px',
      fontSize: 14,
      fontWeight: 600,
      cursor: 'pointer',
      transition: 'opacity 0.2s, transform 0.2s',
    },
    hero: {
      paddingTop: 160,
      paddingBottom: 120,
      textAlign: 'center' as const,
      position: 'relative' as const,
    },
    heroBadge: {
      display: 'inline-block',
      background: 'rgba(99,102,241,0.15)',
      border: '1px solid rgba(99,102,241,0.3)',
      borderRadius: 100,
      padding: '6px 16px',
      fontSize: 13,
      color: '#a5b4fc',
      marginBottom: 24,
    },
    heroTitle: {
      fontSize: 'clamp(48px, 8vw, 80px)',
      fontWeight: 800,
      lineHeight: 1.1,
      letterSpacing: '-2px',
      margin: '0 0 24px',
      background: 'linear-gradient(135deg, #ffffff 0%, #a5b4fc 50%, #8b5cf6 100%)',
      WebkitBackgroundClip: 'text' as const,
      WebkitTextFillColor: 'transparent' as const,
    },
    heroSubtitle: {
      fontSize: 20,
      color: '#94a3b8',
      maxWidth: 560,
      margin: '0 auto 48px',
      lineHeight: 1.7,
    },
    heroCta: {
      display: 'flex',
      gap: 16,
      justifyContent: 'center',
      flexWrap: 'wrap' as const,
    },
    btnLarge: {
      background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
      color: 'white',
      border: 'none',
      borderRadius: 12,
      padding: '16px 32px',
      fontSize: 16,
      fontWeight: 600,
      cursor: 'pointer',
      textDecoration: 'none',
      display: 'inline-block',
    },
    btnOutline: {
      background: 'transparent',
      color: '#e2e8f0',
      border: '1px solid rgba(226,232,240,0.2)',
      borderRadius: 12,
      padding: '16px 32px',
      fontSize: 16,
      fontWeight: 600,
      cursor: 'pointer',
      textDecoration: 'none',
      display: 'inline-block',
    },
    heroGlow: {
      position: 'absolute' as const,
      top: '50%', left: '50%',
      transform: 'translate(-50%, -50%)',
      width: 600, height: 600,
      background: 'radial-gradient(circle, rgba(99,102,241,0.08) 0%, transparent 70%)',
      pointerEvents: 'none' as const,
      zIndex: -1,
    },
    section: {
      maxWidth: 1200,
      margin: '0 auto',
      padding: '80px 24px',
    },
    sectionTitle: {
      fontSize: 36,
      fontWeight: 700,
      textAlign: 'center' as const,
      marginBottom: 12,
      letterSpacing: '-0.5px',
    },
    sectionSub: {
      color: '#64748b',
      textAlign: 'center' as const,
      marginBottom: 56,
      fontSize: 16,
    },
    featuresGrid: {
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
      gap: 24,
    },
    featureCard: {
      background: 'rgba(255,255,255,0.03)',
      border: '1px solid rgba(255,255,255,0.06)',
      borderRadius: 16,
      padding: 28,
      transition: 'border-color 0.2s, transform 0.2s',
    },
    featureIcon: {
      width: 56, height: 56,
      borderRadius: 12,
      background: 'rgba(99,102,241,0.12)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      marginBottom: 20,
      color: '#a5b4fc',
    },
    featureTitle: {
      fontSize: 17,
      fontWeight: 600,
      marginBottom: 8,
    },
    featureDesc: {
      color: '#64748b',
      fontSize: 14,
      lineHeight: 1.7,
    },
    downloadsGrid: {
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
      gap: 20,
    },
    downloadCard: {
      background: 'rgba(255,255,255,0.03)',
      border: '1px solid rgba(255,255,255,0.06)',
      borderRadius: 16,
      padding: 28,
      textAlign: 'center' as const,
      transition: 'border-color 0.2s',
    },
    downloadIcon: {
      fontSize: 40,
      marginBottom: 12,
      height: 48,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
    },
    downloadName: {
      fontSize: 16,
      fontWeight: 600,
      marginBottom: 16,
    },
    downloadBtn: {
      display: 'inline-block',
      background: 'rgba(99,102,241,0.15)',
      border: '1px solid rgba(99,102,241,0.3)',
      color: '#a5b4fc',
      borderRadius: 8,
      padding: '10px 24px',
      fontSize: 14,
      fontWeight: 500,
      textDecoration: 'none',
      cursor: 'pointer',
      transition: 'background 0.2s',
    },
    divider: {
      height: 1,
      background: 'linear-gradient(90deg, transparent, rgba(99,102,241,0.2), transparent)',
      margin: '0 24px',
    },
    footer: {
      textAlign: 'center' as const,
      padding: '40px 24px',
      color: '#334155',
      fontSize: 14,
    },
    langBtn: {
      background: 'transparent',
      border: '1px solid rgba(148,163,184,0.2)',
      borderRadius: 6,
      color: '#94a3b8',
      padding: '6px 12px',
      fontSize: 13,
      cursor: 'pointer',
      position: 'relative' as const,
    },
    langDropdown: {
      position: 'absolute' as const,
      top: '100%',
      right: 0,
      marginTop: 4,
      background: '#1e293b',
      border: '1px solid rgba(255,255,255,0.1)',
      borderRadius: 8,
      overflow: 'hidden',
      minWidth: 130,
      zIndex: 200,
    },
    langOption: {
      padding: '10px 16px',
      fontSize: 14,
      cursor: 'pointer',
      color: '#e2e8f0',
      background: 'transparent',
      border: 'none',
      width: '100%',
      textAlign: 'left' as const,
      transition: 'background 0.15s',
    },
  }

  return (
    <div style={s.root}>
      {/* Nav */}
      <nav style={s.nav}>
        <div style={s.navInner}>
          <span style={s.logo}>RemoteCtl</span>
          <ul style={s.navLinks}>
            <li><a href="#features" style={s.navLink}>{t('nav_features')}</a></li>
            <li><a href="#download" style={s.navLink}>{t('nav_download')}</a></li>
            <li style={s.navLink} onClick={() => navigate('/admin')}>{t('nav_admin')}</li>
            <li style={{position:'relative'}}>
              <button style={s.langBtn} onClick={() => setShowLang(v => !v)}>
                🌐 {LANG_NAMES[lang]}
              </button>
              {showLang && (
                <div style={s.langDropdown}>
                  {(['zh','en','zh_TW'] as Lang[]).map(l => (
                    <button
                      key={l}
                      style={{...s.langOption, fontWeight: l === lang ? 600 : 400, color: l === lang ? '#a5b4fc' : '#e2e8f0'}}
                      onClick={() => { setLang(l); setShowLang(false) }}
                    >
                      {LANG_NAMES[l]}
                    </button>
                  ))}
                </div>
              )}
            </li>
          </ul>
          <button style={s.btnPrimary} onClick={() => navigate('/control')}>
            {t('nav_connect')}
          </button>
        </div>
      </nav>

      {/* Hero */}
      <div style={s.hero}>
        <div style={s.heroGlow} />
        <div style={s.heroBadge}>{t('hero_title')}</div>
        <h1 style={s.heroTitle}>RemoteCtl</h1>
        <p style={s.heroSubtitle}>{t('hero_subtitle')}</p>
        <div style={s.heroCta}>
          <button style={s.btnLarge} onClick={() => navigate('/control')}>
            {t('hero_start')} →
          </button>
          <a href="#download" style={s.btnOutline}>
            {t('hero_download')}
          </a>
        </div>
      </div>

      {/* Features */}
      <div style={s.divider} />
      <div id="features" style={s.section}>
        <h2 style={s.sectionTitle}>{t('nav_features')}</h2>
        <div style={s.featuresGrid}>
          {featureKeys.map(f => (
            <div key={f.titleKey} style={s.featureCard}>
              <div style={s.featureIcon}>{f.icon}</div>
              <div style={s.featureTitle}>{t(f.titleKey)}</div>
              <div style={s.featureDesc}>{t(f.descKey)}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Downloads */}
      <div style={s.divider} />
      <div id="download" style={s.section}>
        <h2 style={s.sectionTitle}>{t('dl_title')}</h2>
        <p style={s.sectionSub}>
          {version ? `${t('dl_latest')}: ${version}` : t('dl_subtitle')}
        </p>
        <div style={s.downloadsGrid}>
          {platforms.map(p => (
            <div key={p.nameKey} style={s.downloadCard}>
              <div style={s.downloadIcon}>{p.icon}</div>
              <div style={s.downloadName}>{t(p.nameKey)}</div>
              <a href={downloadUrl(p)} style={s.downloadBtn} target="_blank" rel="noopener noreferrer">
                {version ? `↓ ${version}` : t('dl_github')}
              </a>
            </div>
          ))}
        </div>
        <p style={{textAlign:'center', marginTop:32, color:'#334155', fontSize:14}}>
          <a href={RELEASES_PAGE} style={{color:'#6366f1'}} target="_blank" rel="noopener noreferrer">
            {t('dl_github')} →
          </a>
        </p>
      </div>

      <div style={s.divider} />
      <footer style={s.footer}>
        <p>© 2025 RemoteCtl · WebRTC</p>
      </footer>
    </div>
  )
}
