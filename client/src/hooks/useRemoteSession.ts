import { useCallback, useEffect, useRef, useState } from 'react'
import {
  deriveSessionKey,
  encrypt,
  exportPublicKey,
  generateKeyPair,
  type ECDHKeyPair,
} from '../crypto'
import type { ConnectionState, DeviceInfo, InputEvent, WsMessage } from '../types'

interface SessionOptions {
  serverURL: string
  deviceID: string
  password: string
}

interface RemoteSession {
  state: ConnectionState
  error: string
  videoStream: MediaStream | null
  devices: DeviceInfo[]
  connect: (opts: SessionOptions) => void
  disconnect: () => void
  sendInput: (e: InputEvent) => void
  fetchDevices: (serverURL: string) => Promise<void>
}

interface E2EEState {
  keyPair: ECDHKeyPair
  sessionKey: CryptoKey | null
}

export function useRemoteSession(): RemoteSession {
  const ws = useRef<WebSocket | null>(null)
  const pc = useRef<RTCPeerConnection | null>(null)
  const e2ee = useRef<E2EEState | null>(null)
  const inputDC = useRef<RTCDataChannel | null>(null)     // reliable: clicks/keys
  const inputMoveDC = useRef<RTCDataChannel | null>(null) // unreliable: mousemove
  const iceServers = useRef<RTCIceServer[]>([{ urls: 'stun:stun.l.google.com:19302' }])

  const [state, setState] = useState<ConnectionState>('idle')
  const [error, setError] = useState('')
  const [videoStream, setVideoStream] = useState<MediaStream | null>(null)
  const [devices, setDevices] = useState<DeviceInfo[]>([])

  const disconnect = useCallback(() => {
    inputDC.current = null
    inputMoveDC.current = null
    pc.current?.close()
    pc.current = null
    ws.current?.close()
    ws.current = null
    e2ee.current = null
    iceServers.current = [{ urls: 'stun:stun.l.google.com:19302' }]
    setVideoStream(null)
    setState('idle')
  }, [])

  const connect = useCallback(({ serverURL, deviceID, password }: SessionOptions) => {
    disconnect()
    setState('connecting')
    setError('')

    const u = new URL(serverURL)
    u.protocol = u.protocol === 'https:' ? 'wss:' : 'ws:'
    u.pathname = '/ws/viewer'

    const socket = new WebSocket(u.toString())
    ws.current = socket

    socket.onopen = () => {
      socket.send(JSON.stringify({
        type: 'connect',
        payload: { device_id: deviceID, password },
      }))
    }

    socket.onmessage = async (ev) => {
      const msg: WsMessage = JSON.parse(ev.data as string)

      switch (msg.type) {

        case 'connected': {
          // Store ICE servers (includes TURN if configured on the relay)
          const { ice_servers } = msg.payload as { ice_servers?: RTCIceServer[] }
          if (ice_servers && ice_servers.length > 0) {
            iceServers.current = ice_servers
          }
          break
        }

        case 'key_offer': {
          // ECDH key exchange for encrypted input events
          const offer = msg.payload as { public_key: string }
          try {
            const keyPair = await generateKeyPair()
            const sessionKey = await deriveSessionKey(keyPair, offer.public_key)
            e2ee.current = { keyPair, sessionKey }
            const myPubKey = await exportPublicKey(keyPair)
            socket.send(JSON.stringify({
              type: 'key_answer',
              payload: { public_key: myPubKey },
            }))
          } catch (err) {
            setError(`Key exchange failed: ${err}`)
            setState('error')
            socket.close()
          }
          break
        }

        case 'rtc_offer': {
          // SDP offer from agent — create PeerConnection and reply with answer
          const { sdp } = msg.payload as { sdp: string }
          try {
            const peerConn = new RTCPeerConnection({
              iceServers: iceServers.current,
            })
            pc.current = peerConn

            // Trickle ICE — send candidates to agent via server
            peerConn.onicecandidate = (e) => {
              if (e.candidate) {
                socket.send(JSON.stringify({
                  type: 'rtc_ice_viewer',
                  payload: {
                    candidate: e.candidate.candidate,
                    sdp_mid: e.candidate.sdpMid ?? '',
                  },
                }))
              }
            }

            // DataChannels from agent — P2P low-latency path
            peerConn.ondatachannel = (e) => {
              if (e.channel.label === 'input') {
                inputDC.current = e.channel
              } else if (e.channel.label === 'input-move') {
                inputMoveDC.current = e.channel
              }
            }

            // Video track from agent — expose as MediaStream
            peerConn.ontrack = (e) => {
              setVideoStream(e.streams[0] ?? new MediaStream([e.track]))
              setState('connected')
            }

            peerConn.onconnectionstatechange = () => {
              const s = peerConn.connectionState
              if (s === 'failed' || s === 'closed') {
                setError('WebRTC connection failed')
                setState('error')
              }
            }

            await peerConn.setRemoteDescription({ type: 'offer', sdp })
            const answer = await peerConn.createAnswer()
            await peerConn.setLocalDescription(answer)

            socket.send(JSON.stringify({
              type: 'rtc_answer',
              payload: { sdp: answer.sdp },
            }))
          } catch (err) {
            setError(`WebRTC setup failed: ${err}`)
            setState('error')
            socket.close()
          }
          break
        }

        case 'rtc_ice_agent': {
          // ICE candidate from agent
          const { candidate, sdp_mid } = msg.payload as { candidate: string; sdp_mid: string }
          if (pc.current) {
            try {
              await pc.current.addIceCandidate({ candidate, sdpMid: sdp_mid })
            } catch {
              // Ignore — can happen if peer closes first
            }
          }
          break
        }

        case 'agent_offline':
          setError('agent disconnected')
          setState('error')
          socket.close()
          break

        case 'error':
          setError((msg.payload as { message: string }).message)
          setState('error')
          socket.close()
          break
      }
    }

    socket.onerror = () => {
      // Only report as error if WebRTC hasn't taken over yet
      if (!pc.current) {
        setError('WebSocket connection error')
        setState('error')
      }
    }

    socket.onclose = () => {
      e2ee.current = null
      ws.current = null
    }
  }, [disconnect])

  const sendInput = useCallback(async (ev: InputEvent) => {
    // mousemove → unreliable channel: stale positions are worthless to retransmit
    const isMove = ev.event === 'mousemove'
    const dc = isMove
      ? (inputMoveDC.current?.readyState === 'open' ? inputMoveDC.current : inputDC.current)
      : inputDC.current
    if (dc?.readyState === 'open') {
      dc.send(JSON.stringify(ev))
      return
    }
    // Fallback: WebSocket E2EE relay
    if (ws.current?.readyState !== WebSocket.OPEN) return
    if (!e2ee.current?.sessionKey) return
    try {
      const plaintext = new TextEncoder().encode(JSON.stringify(ev))
      const data = await encrypt(e2ee.current.sessionKey, plaintext)
      ws.current.send(JSON.stringify({ type: 'input_enc', payload: { data } }))
    } catch {
      // best effort
    }
  }, [])

  const fetchDevices = useCallback(async (serverURL: string) => {
    try {
      const u = new URL('/api/devices', serverURL)
      const res = await fetch(u.toString())
      const data: DeviceInfo[] = await res.json()
      setDevices(data)
    } catch {
      setDevices([])
    }
  }, [])

  useEffect(() => () => {
    pc.current?.close()
    ws.current?.close()
  }, [])

  return { state, error, videoStream, devices, connect, disconnect, sendInput, fetchDevices }
}
