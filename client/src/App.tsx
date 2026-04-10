import { useState } from 'react'
import ConnectPanel from './components/ConnectPanel'
import RemoteScreen from './components/RemoteScreen'
import { useRemoteSession } from './hooks/useRemoteSession'

export default function App() {
  const session = useRemoteSession()
  const [connectedDevice, setConnectedDevice] = useState('')

  const handleConnect = (serverURL: string, deviceID: string, password: string) => {
    setConnectedDevice(deviceID)
    session.connect({ serverURL, deviceID, password })
  }

  if (session.state === 'connected') {
    const deviceInfo = session.devices.find(d => d.id === connectedDevice)
    return (
      <RemoteScreen
        videoStream={session.videoStream}
        onInput={session.sendInput}
        onDisconnect={session.disconnect}
        deviceName={connectedDevice}
        remotePlatform={deviceInfo?.platform ?? ''}
      />
    )
  }

  return (
    <ConnectPanel
      onConnect={handleConnect}
      onFetchDevices={session.fetchDevices}
      devices={session.devices}
      error={session.error}
      connecting={session.state === 'connecting'}
    />
  )
}
