import { useState, useEffect, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'

interface VersionInfo {
  version: string
}

const RELEASES_BASE = 'https://github.com/bsh888/remotectl-releases/releases/download'
const RELEASES_PAGE = 'https://github.com/bsh888/remotectl-releases/releases'

const features = [
  {
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
        <path d="M15 10l4.553-2.069A1 1 0 0121 8.868V15.132a1 1 0 01-1.447.9L15 14M3 8a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V8z"/>
      </svg>
    ),
    title: 'H.264 硬件编码',
    desc: 'macOS 使用 VideoToolbox，Windows/Linux 使用 x264，低码率高画质',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
        <circle cx="12" cy="12" r="3"/>
        <path d="M12 2v3M12 19v3M4.22 4.22l2.12 2.12M17.66 17.66l2.12 2.12M2 12h3M19 12h3M4.22 19.78l2.12-2.12M17.66 6.34l2.12-2.12"/>
      </svg>
    ),
    title: 'WebRTC P2P',
    desc: '视频流点对点直连，服务器不经手视频数据，超低延迟体验',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
        <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
        <path d="M7 11V7a5 5 0 0110 0v4"/>
      </svg>
    ),
    title: 'E2EE 输入加密',
    desc: 'ECDH P-256 + AES-256-GCM 端对端加密，服务器无法解密输入事件',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
        <rect x="2" y="3" width="20" height="14" rx="2"/>
        <path d="M8 21h8M12 17v4"/>
      </svg>
    ),
    title: '跨平台支持',
    desc: 'macOS / Windows / Linux 被控端，任意设备通过浏览器或 App 控制',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
        <path d="M13 10V3L4 14h7v7l9-11h-7z"/>
      </svg>
    ),
    title: '低延迟鼠标',
    desc: '本地光标叠加层即时反馈，输入事件走 P2P DataChannel',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{width:32,height:32}}>
        <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/>
      </svg>
    ),
    title: '会话内聊天',
    desc: '控制端与被控端实时文字消息和文件互传，支持系统通知',
  },
]

const AppleLogo = () => (
  <svg viewBox="0 0 170 170" fill="currentColor" style={{width:36,height:36}}>
    <path d="M150.37 130.25c-2.45 5.66-5.35 10.87-8.71 15.66-4.58 6.53-8.33 11.05-11.22 13.56-4.48 4.12-9.28 6.23-14.42 6.35-3.69 0-8.14-1.05-13.32-3.18-5.2-2.12-9.97-3.17-14.34-3.17-4.58 0-9.49 1.05-14.75 3.17-5.26 2.13-9.5 3.24-12.74 3.35-4.93.21-9.84-1.96-14.75-6.52-3.13-2.73-7.04-7.41-11.73-14.04-5.03-7.08-9.17-15.29-12.41-24.65C.36 110.68 0 101.13 0 91.66c0-10.86 2.35-20.22 7.05-28.07 3.69-6.3 8.6-11.27 14.75-14.92 6.15-3.65 12.79-5.51 19.95-5.63 3.91 0 9.05 1.21 15.43 3.59 6.36 2.39 10.45 3.6 12.24 3.6 1.34 0 5.88-1.42 13.57-4.24 7.28-2.62 13.42-3.7 18.45-3.28 13.63 1.1 23.87 6.47 30.68 16.15-12.19 7.39-18.22 17.73-18.1 31 .11 10.34 3.86 18.94 11.23 25.77 3.34 3.17 7.07 5.62 11.22 7.36-.9 2.61-1.85 5.11-2.86 7.51zM119.11 7.24c0 8.1-2.96 15.67-8.86 22.67-7.12 8.32-15.73 13.13-25.07 12.38a25.3 25.3 0 0 1-.19-3.07c0-7.78 3.39-16.1 9.4-22.91 3-3.45 6.82-6.31 11.45-8.6C110.47 5.5 114.84 4.26 118.95 4c.11 1.08.16 2.16.16 3.24z"/>
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

const platforms: { name: string; icon: ReactNode; fileKey: string; ext: string; label: string }[] = [
  { name: 'macOS', icon: <AppleLogo />, fileKey: 'macos', ext: 'zip', label: 'remotectl-app-macos' },
  { name: 'Windows', icon: <WindowsLogo />, fileKey: 'windows', ext: 'zip', label: 'remotectl-app-windows-amd64' },
  { name: 'Linux App', icon: '🐧', fileKey: 'linux', ext: 'tar.gz', label: 'remotectl-app-linux-amd64' },
  { name: 'Linux Agent', icon: '⚙️', fileKey: 'agent', ext: 'tar.gz', label: 'remotectl-agent-linux-amd64' },
]

export default function LandingPage() {
  const navigate = useNavigate()
  const [version, setVersion] = useState<string>('')
  const [scrolled, setScrolled] = useState(false)

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
  }

  return (
    <div style={s.root}>
      {/* Nav */}
      <nav style={s.nav}>
        <div style={s.navInner}>
          <span style={s.logo}>RemoteCtl</span>
          <ul style={s.navLinks}>
            <li><a href="#features" style={s.navLink}>功能</a></li>
            <li><a href="#download" style={s.navLink}>下载</a></li>
            <li
              style={s.navLink}
              onClick={() => navigate('/admin')}
            >管理后台</li>
          </ul>
          <button style={s.btnPrimary} onClick={() => navigate('/control')}>
            开始远程控制
          </button>
        </div>
      </nav>

      {/* Hero */}
      <div style={s.hero}>
        <div style={s.heroGlow} />
        <div style={s.heroBadge}>跨平台远程桌面系统</div>
        <h1 style={s.heroTitle}>RemoteCtl</h1>
        <p style={s.heroSubtitle}>
          H.264 硬件编码 · WebRTC P2P · 端对端加密<br/>
          macOS / Windows / Linux 被控端，浏览器或 App 控制
        </p>
        <div style={s.heroCta}>
          <button style={s.btnLarge} onClick={() => navigate('/control')}>
            开始远程控制 →
          </button>
          <a href="#download" style={s.btnOutline}>
            下载客户端
          </a>
        </div>
      </div>

      {/* Features */}
      <div style={s.divider} />
      <div id="features" style={s.section}>
        <h2 style={s.sectionTitle}>核心功能</h2>
        <p style={s.sectionSub}>专为低延迟远程控制设计，安全可靠</p>
        <div style={s.featuresGrid}>
          {features.map(f => (
            <div key={f.title} style={s.featureCard}>
              <div style={s.featureIcon}>{f.icon}</div>
              <div style={s.featureTitle}>{f.title}</div>
              <div style={s.featureDesc}>{f.desc}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Downloads */}
      <div style={s.divider} />
      <div id="download" style={s.section}>
        <h2 style={s.sectionTitle}>下载</h2>
        <p style={s.sectionSub}>
          {version ? `当前版本 ${version}` : '前往 Releases 页面下载最新版本'}
        </p>
        <div style={s.downloadsGrid}>
          {platforms.map(p => (
            <div key={p.name} style={s.downloadCard}>
              <div style={s.downloadIcon}>{p.icon}</div>
              <div style={s.downloadName}>{p.name}</div>
              <a href={downloadUrl(p)} style={s.downloadBtn} target="_blank" rel="noopener noreferrer">
                {version ? `下载 ${version}` : '查看 Releases'}
              </a>
            </div>
          ))}
        </div>
        <p style={{textAlign:'center', marginTop:32, color:'#334155', fontSize:14}}>
          服务器包含 <code style={{color:'#6366f1'}}>remotectl-server-linux-*</code>，下载后解压运行 install.sh 一键部署。
          <a href={RELEASES_PAGE} style={{color:'#6366f1', marginLeft:8}} target="_blank" rel="noopener noreferrer">
            查看所有版本 →
          </a>
        </p>
      </div>

      {/* Platform Support */}
      <div style={s.divider} />
      <div style={s.section}>
        <h2 style={s.sectionTitle}>平台支持</h2>
        <div style={{overflowX:'auto', marginTop:40}}>
          <table style={{
            width:'100%', borderCollapse:'collapse',
            background:'rgba(255,255,255,0.02)',
            borderRadius:12, overflow:'hidden',
          }}>
            <thead>
              <tr style={{borderBottom:'1px solid rgba(255,255,255,0.06)'}}>
                {['平台','控制端','被控端'].map(h => (
                  <th key={h} style={{padding:'16px 24px', textAlign:'left', color:'#64748b', fontSize:14, fontWeight:600}}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {[
                ['macOS', '✅ App + 浏览器', '✅ App 内置'],
                ['Windows', '✅ App + 浏览器', '✅ App 内置'],
                ['Linux', '✅ App + 浏览器', '✅ App 内置 / 独立 Agent'],
                ['iOS', '✅ App', '❌'],
                ['Android', '✅ App', '❌'],
              ].map((row, i) => (
                <tr key={i} style={{borderBottom:'1px solid rgba(255,255,255,0.04)'}}>
                  {row.map((cell, j) => (
                    <td key={j} style={{padding:'14px 24px', fontSize:14, color: j===0 ? '#e2e8f0' : '#94a3b8'}}>{cell}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div style={s.divider} />
      <footer style={s.footer}>
        <p>© 2025 RemoteCtl · WebRTC 跨平台远程桌面</p>
      </footer>
    </div>
  )
}
