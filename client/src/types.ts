export type ConnectionState = 'idle' | 'connecting' | 'connected' | 'error'

export interface InputEvent {
  event: 'mousemove' | 'mousedown' | 'mouseup' | 'click' | 'dblclick' | 'scroll' | 'keydown' | 'keyup' | 'viewport'
  x?: number
  y?: number
  button?: number
  key?: string
  code?: string
  mods?: string[]
  dx?: number
  dy?: number
  vw?: number  // viewport physical width (viewport event only)
  vh?: number  // viewport physical height (viewport event only)
}

export interface WsMessage {
  type: string
  payload?: unknown
}
