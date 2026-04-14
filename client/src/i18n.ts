import { useContext, useState, useCallback } from 'react'

export type Lang = 'zh' | 'en' | 'zh_TW'

const STORAGE_KEY = 'rc_lang'

export function loadSavedLang(): Lang {
  const v = localStorage.getItem(STORAGE_KEY)
  if (v === 'en' || v === 'zh_TW') return v
  return 'zh'
}

export function saveLang(lang: Lang) {
  localStorage.setItem(STORAGE_KEY, lang)
}

// ── Translations ──────────────────────────────────────────────────────────────

type Dict = Record<string, string>

const zh: Dict = {
  // nav
  nav_features: '功能',
  nav_download: '下载',
  nav_admin: '管理后台',
  nav_connect: '远程控制',
  // hero
  hero_title: '跨平台远程桌面系统',
  hero_subtitle: '基于 WebRTC P2P，H.264 硬件编码，端对端加密',
  hero_start: '开始远程控制',
  hero_download: '下载客户端',
  // features
  feat_h264_title: 'H.264 硬件编码',
  feat_h264_desc: 'macOS 使用 VideoToolbox，Windows/Linux 使用 x264，低码率高画质',
  feat_webrtc_title: 'WebRTC P2P',
  feat_webrtc_desc: '视频流点对点直连，服务器不经手视频数据，超低延迟体验',
  feat_e2ee_title: 'E2EE 输入加密',
  feat_e2ee_desc: 'ECDH P-256 + AES-256-GCM 端对端加密，服务器无法解密输入事件',
  feat_cross_title: '跨平台支持',
  feat_cross_desc: 'macOS / Windows / Linux 被控端，任意设备通过浏览器或 App 控制',
  feat_latency_title: '低延迟鼠标',
  feat_latency_desc: '本地光标叠加层即时反馈，输入事件走 P2P DataChannel',
  feat_chat_title: '会话内聊天',
  feat_chat_desc: '支持文字和文件传输，DataChannel 直连，无需服务器中转',
  // download
  dl_title: '下载客户端',
  dl_subtitle: '被控端 Agent、桌面 App（含控制端与被控端）',
  dl_latest: '最新版本',
  dl_agent_title: 'Agent（仅被控端）',
  dl_agent_desc: '服务器/无 GUI 环境专用',
  dl_app_title: '桌面 App',
  dl_app_desc: '含控制端 + 被控端',
  dl_server_title: '信令服务器',
  dl_server_desc: '自托管部署',
  dl_github: '查看所有版本',
  // platform table
  platform: '平台',
  file: '文件',
  agent_linux: 'Linux Agent',
  app_macos: 'macOS App',
  app_windows: 'Windows App',
  app_linux: 'Linux App',
  server_linux: 'Linux Server',
  // connect panel
  recent: '最近连接',
  remove: '移除',
  server_url: '服务器地址',
  device_id: '设备 ID',
  device_id_hint: '9位数字设备ID',
  connect_pwd: '连接密码',
  connect_pwd_hint: '被控端显示的8位数字',
  connecting: '连接中…',
  connect: '连接',
  // remote screen
  paste: '粘贴',
  paste_prompt: '粘贴内容到此处（Ctrl+V / ⌘V）：',
  ctrl_swap_title: '勾选后 Ctrl+C/V/Z 等会转换为 Mac 的 Cmd+C/V/Z',
  paste_title: '将本地剪贴板文本发送到远程（也可在视频区域直接 Ctrl+V）',
  keyboard: '⌨️',
  disconnect: '断开',
  connecting_webrtc: '正在建立 WebRTC 连接…',
  hint_click: '单击 → 左键',
  hint_longpress: '长按 → 右键',
  hint_scroll: '双指滑动 → 滚轮',
  hint_keyboard: '⌨️ → 键盘',
  // admin - login
  admin_title: '管理后台',
  admin_password: '管理员密码',
  login: '登录',
  login_error: '密码错误',
  logout: '退出登录',
  // admin - nav
  dashboard: '概览',
  agents: '设备',
  tokens: '访问令牌',
  // admin - dashboard
  online_devices: '在线设备',
  total_viewers: '控制端总数',
  configured_tokens: '已配置令牌',
  // admin - agents
  device: '设备',
  device_id_col: '设备 ID',
  name: '名称',
  platform_col: '平台',
  host_info: '主机信息',
  viewers: '控制端',
  no_agents: '暂无在线设备',
  // admin - tokens
  add_token: '添加令牌',
  device_id_label: '设备 ID',
  secret_label: '密钥',
  add: '添加',
  cancel: '取消',
  save: '保存',
  edit: '修改',
  delete: '删除',
  delete_token_title: '删除令牌',
  delete_token_msg: '确认删除该设备令牌？',
  confirm: '确认删除',
  no_tokens: '暂无令牌',
}

const en: Dict = {
  nav_features: 'Features',
  nav_download: 'Download',
  nav_admin: 'Admin',
  nav_connect: 'Remote Control',
  hero_title: 'Cross-Platform Remote Desktop',
  hero_subtitle: 'WebRTC P2P, H.264 hardware encoding, end-to-end encryption',
  hero_start: 'Start Remote Control',
  hero_download: 'Download App',
  feat_h264_title: 'H.264 Hardware Encoding',
  feat_h264_desc: 'VideoToolbox on macOS, x264 on Windows/Linux — low bitrate, high quality',
  feat_webrtc_title: 'WebRTC P2P',
  feat_webrtc_desc: 'Video streams directly peer-to-peer, server never touches video data',
  feat_e2ee_title: 'E2EE Input Encryption',
  feat_e2ee_desc: 'ECDH P-256 + AES-256-GCM end-to-end encryption for all input events',
  feat_cross_title: 'Cross-Platform',
  feat_cross_desc: 'macOS / Windows / Linux host, control from any browser or App',
  feat_latency_title: 'Ultra-Low Latency Mouse',
  feat_latency_desc: 'Local cursor overlay for instant feedback, input via P2P DataChannel',
  feat_chat_title: 'In-Session Chat',
  feat_chat_desc: 'Text and file transfer via DataChannel, no server relay needed',
  dl_title: 'Download',
  dl_subtitle: 'Host agent, desktop app (includes controller + host)',
  dl_latest: 'Latest version',
  dl_agent_title: 'Agent (host only)',
  dl_agent_desc: 'For servers / headless environments',
  dl_app_title: 'Desktop App',
  dl_app_desc: 'Includes controller + host',
  dl_server_title: 'Signaling Server',
  dl_server_desc: 'Self-hosted deployment',
  dl_github: 'All releases',
  platform: 'Platform',
  file: 'File',
  agent_linux: 'Linux Agent',
  app_macos: 'macOS App',
  app_windows: 'Windows App',
  app_linux: 'Linux App',
  server_linux: 'Linux Server',
  recent: 'Recent',
  remove: 'Remove',
  server_url: 'Server URL',
  device_id: 'Device ID',
  device_id_hint: '9-digit device ID',
  connect_pwd: 'Session Password',
  connect_pwd_hint: '8-digit code shown on host',
  connecting: 'Connecting…',
  connect: 'Connect',
  paste: 'Paste',
  paste_prompt: 'Paste here (Ctrl+V / ⌘V):',
  ctrl_swap_title: 'Swap Ctrl↔Cmd for Mac shortcuts (Ctrl+C/V/Z → Cmd+C/V/Z)',
  paste_title: 'Send clipboard text to remote (or use Ctrl+V in video area)',
  keyboard: '⌨️',
  disconnect: 'Disconnect',
  connecting_webrtc: 'Establishing WebRTC connection…',
  hint_click: 'Tap → Left click',
  hint_longpress: 'Long press → Right click',
  hint_scroll: 'Two-finger swipe → Scroll',
  hint_keyboard: '⌨️ → Keyboard',
  admin_title: 'Admin',
  admin_password: 'Admin Password',
  login: 'Login',
  login_error: 'Wrong password',
  logout: 'Logout',
  dashboard: 'Dashboard',
  agents: 'Devices',
  tokens: 'Tokens',
  online_devices: 'Online Devices',
  total_viewers: 'Total Viewers',
  configured_tokens: 'Configured Tokens',
  device: 'Device',
  device_id_col: 'Device ID',
  name: 'Name',
  platform_col: 'Platform',
  host_info: 'Host Info',
  viewers: 'Viewers',
  no_agents: 'No devices online',
  add_token: 'Add Token',
  device_id_label: 'Device ID',
  secret_label: 'Secret',
  add: 'Add',
  cancel: 'Cancel',
  save: 'Save',
  edit: 'Edit',
  delete: 'Delete',
  delete_token_title: 'Delete Token',
  delete_token_msg: 'Delete this device token?',
  confirm: 'Confirm',
  no_tokens: 'No tokens configured',
}

const zh_TW: Dict = {
  nav_features: '功能',
  nav_download: '下載',
  nav_admin: '管理後台',
  nav_connect: '遠程控制',
  hero_title: '跨平台遠程桌面系統',
  hero_subtitle: '基於 WebRTC P2P，H.264 硬體編碼，端對端加密',
  hero_start: '開始遠程控制',
  hero_download: '下載客戶端',
  feat_h264_title: 'H.264 硬體編碼',
  feat_h264_desc: 'macOS 使用 VideoToolbox，Windows/Linux 使用 x264，低碼率高畫質',
  feat_webrtc_title: 'WebRTC P2P',
  feat_webrtc_desc: '視頻串流點對點直連，伺服器不經手視頻數據，超低延遲體驗',
  feat_e2ee_title: 'E2EE 輸入加密',
  feat_e2ee_desc: 'ECDH P-256 + AES-256-GCM 端對端加密，伺服器無法解密輸入事件',
  feat_cross_title: '跨平台支援',
  feat_cross_desc: 'macOS / Windows / Linux 被控端，任意裝置透過瀏覽器或 App 控制',
  feat_latency_title: '低延遲滑鼠',
  feat_latency_desc: '本地游標疊加層即時反饋，輸入事件走 P2P DataChannel',
  feat_chat_title: '會話內聊天',
  feat_chat_desc: '支援文字和檔案傳輸，DataChannel 直連，無需伺服器中轉',
  dl_title: '下載客戶端',
  dl_subtitle: '被控端 Agent、桌面 App（含控制端與被控端）',
  dl_latest: '最新版本',
  dl_agent_title: 'Agent（僅被控端）',
  dl_agent_desc: '伺服器 / 無 GUI 環境專用',
  dl_app_title: '桌面 App',
  dl_app_desc: '含控制端 + 被控端',
  dl_server_title: '信令伺服器',
  dl_server_desc: '自託管部署',
  dl_github: '查看所有版本',
  platform: '平台',
  file: '檔案',
  agent_linux: 'Linux Agent',
  app_macos: 'macOS App',
  app_windows: 'Windows App',
  app_linux: 'Linux App',
  server_linux: 'Linux Server',
  recent: '最近連線',
  remove: '移除',
  server_url: '伺服器地址',
  device_id: '裝置 ID',
  device_id_hint: '9位數字裝置ID',
  connect_pwd: '工作階段密碼',
  connect_pwd_hint: '被控端顯示的8位數字',
  connecting: '連線中…',
  connect: '連線',
  paste: '貼上',
  paste_prompt: '貼上內容到此處（Ctrl+V / ⌘V）：',
  ctrl_swap_title: '勾選後 Ctrl+C/V/Z 等會轉換為 Mac 的 Cmd+C/V/Z',
  paste_title: '將本地剪貼簿文字傳送到遠端（也可在視頻區域直接 Ctrl+V）',
  keyboard: '⌨️',
  disconnect: '中斷',
  connecting_webrtc: '正在建立 WebRTC 連線…',
  hint_click: '點擊 → 左鍵',
  hint_longpress: '長按 → 右鍵',
  hint_scroll: '雙指滑動 → 滾輪',
  hint_keyboard: '⌨️ → 鍵盤',
  admin_title: '管理後台',
  admin_password: '管理員密碼',
  login: '登入',
  login_error: '密碼錯誤',
  logout: '退出登入',
  dashboard: '概覽',
  agents: '裝置',
  tokens: '存取令牌',
  online_devices: '在線裝置',
  total_viewers: '控制端總數',
  configured_tokens: '已設定令牌',
  device: '裝置',
  device_id_col: '裝置 ID',
  name: '名稱',
  platform_col: '平台',
  host_info: '主機資訊',
  viewers: '控制端',
  no_agents: '暫無在線裝置',
  add_token: '新增令牌',
  device_id_label: '裝置 ID',
  secret_label: '密鑰',
  add: '新增',
  cancel: '取消',
  save: '儲存',
  edit: '修改',
  delete: '刪除',
  delete_token_title: '刪除令牌',
  delete_token_msg: '確認刪除該裝置令牌？',
  confirm: '確認刪除',
  no_tokens: '暫無令牌',
}

const dicts: Record<Lang, Dict> = { zh, en, zh_TW }

// ── Context + hook ────────────────────────────────────────────────────────────

export type I18nContextType = {
  lang: Lang
  setLang: (lang: Lang) => void
  t: (key: string) => string
}

import { createContext } from 'react'
export const I18nContext = createContext<I18nContextType>({
  lang: 'zh',
  setLang: () => {},
  t: (k) => k,
})

export function useI18n() {
  return useContext(I18nContext)
}

export function useI18nProvider() {
  const [lang, setLangState] = useState<Lang>(loadSavedLang)

  const setLang = useCallback((l: Lang) => {
    saveLang(l)
    setLangState(l)
  }, [])

  const t = useCallback((key: string) => {
    return dicts[lang][key] ?? dicts['zh'][key] ?? key
  }, [lang])

  return { lang, setLang, t }
}

export const LANG_NAMES: Record<Lang, string> = {
  zh: '简体中文',
  en: 'English',
  zh_TW: '繁體中文',
}
