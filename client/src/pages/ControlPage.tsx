import { useEffect, useRef, useState } from 'react'
import ConnectPanel, { HistoryEntry, loadHistory, saveHistory } from '../components/ConnectPanel'
import RemoteScreen from '../components/RemoteScreen'
import { useRemoteSession } from '../hooks/useRemoteSession'

export default function ControlPage() {
  const session = useRemoteSession()
  const [connectedDevice, setConnectedDevice] = useState('')
  const [history, setHistory] = useState<HistoryEntry[]>(() => loadHistory())
  const lastAttempt = useRef<{ serverURL: string; deviceID: string; password: string } | null>(null)

  // Save to history on successful connection
  useEffect(() => {
    if (session.state === 'connected' && lastAttempt.current) {
      setHistory(prev => saveHistory(prev, { ...lastAttempt.current!, ts: Date.now() }))
    }
  }, [session.state])

  const handleConnect = (serverURL: string, deviceID: string, password: string) => {
    lastAttempt.current = { serverURL, deviceID, password }
    setConnectedDevice(deviceID)
    session.connect({ serverURL, deviceID, password })
  }

  const handleRemoveHistory = (deviceID: string, serverURL: string) => {
    setHistory(prev => {
      const updated = prev.filter(h => !(h.deviceID === deviceID && h.serverURL === serverURL))
      localStorage.setItem('rc_history', JSON.stringify(updated))
      return updated
    })
  }

  if (session.state === 'connected') {
    return (
      <RemoteScreen
        videoStream={session.videoStream}
        onInput={session.sendInput}
        onDisconnect={session.disconnect}
        onViewport={session.sendViewport}
        deviceName={connectedDevice}
        remotePlatform=''
      />
    )
  }

  return (
    <ConnectPanel
      onConnect={handleConnect}
      error={session.error}
      connecting={session.state === 'connecting'}
      history={history}
      onRemoveHistory={handleRemoveHistory}
    />
  )
}
