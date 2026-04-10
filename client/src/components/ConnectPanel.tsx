import { useEffect, useState } from 'react'

interface Props {
  onConnect: (serverURL: string, deviceID: string, password: string) => void
  error: string
  connecting: boolean
}

export default function ConnectPanel({ onConnect, error, connecting }: Props) {
  const [serverURL, setServerURL] = useState(() => localStorage.getItem('rc_server') ?? 'http://localhost:8080')
  const [deviceID, setDeviceID] = useState(() => localStorage.getItem('rc_device') ?? '')
  const [password, setPassword] = useState('')

  useEffect(() => {
    localStorage.setItem('rc_server', serverURL)
  }, [serverURL])

  useEffect(() => {
    localStorage.setItem('rc_device', deviceID)
  }, [deviceID])

  const handleConnect = (e: React.FormEvent) => {
    e.preventDefault()
    onConnect(serverURL, deviceID, password)
  }

  return (
    <div style={styles.container}>
      <div style={styles.card}>
        <h1 style={styles.title}>🖥 RemoteCtl</h1>
        <form onSubmit={handleConnect} style={styles.form}>
          <label style={styles.label}>
            服务器地址
            <input
              style={styles.input}
              value={serverURL}
              onChange={e => setServerURL(e.target.value)}
              placeholder="http://your-server:8080"
              required
            />
          </label>

          <label style={styles.label}>
            设备 ID
            <input
              style={styles.input}
              value={deviceID}
              onChange={e => setDeviceID(e.target.value)}
              placeholder="9位数字设备ID"
              required
            />
          </label>

          <label style={styles.label}>
            连接密码
            <input
              style={styles.input}
              type="password"
              value={password}
              onChange={e => setPassword(e.target.value)}
              placeholder="被控端显示的8位数字"
              required
            />
          </label>

          {error && <div style={styles.error}>{error}</div>}

          <button type="submit" style={styles.btnPrimary} disabled={connecting}>
            {connecting ? '连接中…' : '连接'}
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
  form: {
    display: 'flex',
    flexDirection: 'column',
    gap: 16,
  },
  label: {
    display: 'flex',
    flexDirection: 'column',
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
