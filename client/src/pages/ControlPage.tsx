import { useState } from 'react'
import ConnectPanel from '../components/ConnectPanel'
import RemoteScreen from '../components/RemoteScreen'
import { useRemoteSession } from '../hooks/useRemoteSession'

export default function ControlPage() {
  const session = useRemoteSession()
  const [connectedDevice, setConnectedDevice] = useState('')

  const handleConnect = (serverURL: string, deviceID: string, password: string) => {
    setConnectedDevice(deviceID)
    session.connect({ serverURL, deviceID, password })
  }

  if (session.state === 'connected') {
    return (
      <RemoteScreen
        videoStream={session.videoStream}
        onInput={session.sendInput}
        onDisconnect={session.disconnect}
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
    />
  )
}
