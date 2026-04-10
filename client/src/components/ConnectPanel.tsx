import { useEffect, useState } from 'react'
import type { DeviceInfo } from '../types'

interface Props {
  onConnect: (serverURL: string, deviceID: string, password: string) => void
  onFetchDevices: (serverURL: string) => Promise<void>
  devices: DeviceInfo[]
  error: string
  connecting: boolean
}

export default function ConnectPanel({ onConnect, onFetchDevices, devices, error, connecting }: Props) {
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

  const handleRefresh = () => onFetchDevices(serverURL)

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
            <div style={{ display: 'flex', gap: 8 }}>
              <input
                style={{ ...styles.input, flex: 1 }}
                value={deviceID}
                onChange={e => setDeviceID(e.target.value)}
                placeholder="office-mac"
                required
              />
              <button type="button" style={styles.btnSecondary} onClick={handleRefresh}>
                刷新
              </button>
            </div>
          </label>

          {devices.length > 0 && (
            <div style={styles.deviceList}>
              {devices.map(d => (
                <div
                  key={d.id}
                  style={styles.deviceItem}
                  onClick={() => setDeviceID(d.id)}
                >
                  <span style={styles.dot} />
                  <span style={{ flex: 1 }}>{d.name || d.id}</span>
                  <span style={styles.badge}>{d.platform}</span>
                  {d.viewer_count > 0 && (
                    <span style={styles.viewerBadge}>{d.viewer_count} 人连接</span>
                  )}
                </div>
              ))}
            </div>
          )}

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
  btnSecondary: {
    background: '#334155',
    color: '#e2e8f0',
    border: 'none',
    borderRadius: 6,
    padding: '10px 14px',
    fontSize: 13,
    cursor: 'pointer',
  },
  deviceList: {
    border: '1px solid #334155',
    borderRadius: 6,
    overflow: 'hidden',
  },
  deviceItem: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '10px 12px',
    cursor: 'pointer',
    fontSize: 13,
    borderBottom: '1px solid #1e293b',
    background: '#0f172a',
    transition: 'background 0.15s',
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: '50%',
    background: '#22c55e',
    flexShrink: 0,
  },
  badge: {
    fontSize: 11,
    background: '#334155',
    padding: '2px 6px',
    borderRadius: 4,
    color: '#94a3b8',
  },
  viewerBadge: {
    fontSize: 11,
    background: '#1d4ed8',
    padding: '2px 6px',
    borderRadius: 4,
    color: '#bfdbfe',
  },
  error: {
    background: '#450a0a',
    color: '#fca5a5',
    borderRadius: 6,
    padding: '10px 12px',
    fontSize: 13,
  },
}
