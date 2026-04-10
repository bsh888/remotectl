export type ConnectionState = 'idle' | 'connecting' | 'connected' | 'error'

export interface InputEvent {
  event: 'mousemove' | 'mousedown' | 'mouseup' | 'click' | 'dblclick' | 'scroll' | 'keydown' | 'keyup'
  x?: number
  y?: number
  button?: number
  key?: string
  code?: string
  mods?: string[]
  dx?: number
  dy?: number
}

export interface WsMessage {
  type: string
  payload?: unknown
}
