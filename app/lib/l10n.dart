import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Locale state ──────────────────────────────────────────────────────────────

final localeNotifier = ValueNotifier<Locale>(const Locale('zh'));

/// Detect system locale and map to one of the three supported locales.
Locale _detectSystemLocale() {
  final sys = PlatformDispatcher.instance.locale;
  final lang = sys.languageCode.toLowerCase();
  final country = sys.countryCode?.toUpperCase() ?? '';
  if (lang == 'zh') {
    if (country == 'TW' || country == 'HK' || country == 'MO') {
      return const Locale('zh', 'TW');
    }
    return const Locale('zh');
  }
  if (lang == 'en') return const Locale('en');
  return const Locale('zh'); // default fallback
}

Future<void> loadSavedLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final tag = prefs.getString('locale');
  if (tag == null) {
    // First launch: follow system locale
    localeNotifier.value = _detectSystemLocale();
    return;
  }
  if (tag == 'zh') {
    localeNotifier.value = const Locale('zh');
  } else if (tag == 'en') {
    localeNotifier.value = const Locale('en');
  } else if (tag == 'zh_TW') {
    localeNotifier.value = const Locale('zh', 'TW');
  }
}

Future<void> saveLocale(Locale locale) async {
  final prefs = await SharedPreferences.getInstance();
  String tag;
  if (locale.languageCode == 'zh' && locale.countryCode == 'TW') {
    tag = 'zh_TW';
  } else {
    tag = locale.languageCode;
  }
  await prefs.setString('locale', tag);
  localeNotifier.value = locale;
}

// ── Supported locales + delegates ─────────────────────────────────────────────

const supportedLocales = [
  Locale('zh'),
  Locale('en'),
  Locale('zh', 'TW'),
];

const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

// ── AppLocalizations ──────────────────────────────────────────────────────────

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const delegate = _Delegate();

  bool get _isTW =>
      locale.languageCode == 'zh' && locale.countryCode == 'TW';
  bool get _isEn => locale.languageCode == 'en';

  String _s(String zh, String en, String tw) {
    if (_isEn) return en;
    if (_isTW) return tw;
    return zh;
  }

  // ── Navigation ──────────────────────────────────────────────────────────────
  String get navRemote => _s('远程控制', 'Remote', '遠程控制');
  String get navHosted => _s('共享本机', 'Host', '共享本機');

  // ── main.dart ───────────────────────────────────────────────────────────────
  String get exitConfirmTitle => _s('退出确认', 'Confirm Exit', '退出確認');
  String get exitConfirmContent =>
      _s('当前正在共享屏幕，退出后远程连接将断开。',
          'Screen sharing is active. Exit will disconnect the session.',
          '目前正在共享螢幕，退出後遠程連線將斷開。');
  String get exitCancel => _s('取消', 'Cancel', '取消');
  String get exitConfirm => _s('停止共享并退出', 'Stop & Exit', '停止共享並退出');

  // ── connect_screen.dart ──────────────────────────────────────────────────────
  String get connectSubtitle => _s('远程桌面控制', 'Remote Desktop', '遠程桌面控制');
  String get recentConnections => _s('最近连接', 'RECENT', 'RECENT');
  String get serverAddress => _s('服务器地址', 'Server URL', '伺服器地址');
  String get deviceId => _s('设备 ID', 'Device ID', '裝置 ID');
  String get sessionPassword => _s('会话密码', 'Session Password', '工作階段密碼');
  String get deviceIdHint => _s('9位数字设备ID', '9-digit device ID', '9位數字裝置ID');
  String get sessionPasswordHint =>
      _s('被控端显示的8位数字', '8-digit code shown on host', '被控端顯示的8位數字');
  String get connecting => _s('连接中…', 'Connecting…', '連線中…');
  String get connect => _s('连接', 'Connect', '連線');
  String get deleteRecordTitle => _s('删除记录', 'Delete Record', '刪除記錄');
  String get deleteRecordContent =>
      _s('确认删除该连接记录？', 'Delete this connection record?', '確認刪除此連線記錄？');
  String get cancel => _s('取消', 'Cancel', '取消');
  String get delete => _s('删除', 'Delete', '刪除');

  // ── hosted_screen.dart ───────────────────────────────────────────────────────
  String get connectionConfig => _s('连接配置', 'Connection Config', '連線配置');
  String get serverAddressLabel => _s('服务器地址', 'Server URL', '伺服器地址');
  String get deviceToken => _s('设备密钥', 'Device Token', '裝置密鑰');
  String get deviceTokenHint =>
      _s('用于验证身份的密钥（可选）', 'Auth token (optional)', '用於驗證身份的密鑰（可選）');
  String get displayName => _s('显示名称', 'Display Name', '顯示名稱');
  String get displayNameHint =>
      _s('（默认同设备 ID）', '(defaults to device ID)', '（預設同裝置 ID）');
  String get advancedSettings => _s('高级设置', 'Advanced', '進階設定');
  String get hideAdvanced => _s('收起高级设置', 'Hide Advanced', '收起進階設定');
  String get bitrate => _s('码率 (kbps)', 'Bitrate (kbps)', '碼率 (kbps)');
  String get resolutionScale => _s('分辨率缩放', 'Resolution Scale', '解析度縮放');
  String get caCertPath => _s('CA 证书路径', 'CA Cert Path', 'CA 憑證路徑');
  String get caCertHint =>
      _s('/path/to/server.crt（可选）', '/path/to/server.crt (optional)', '/path/to/server.crt（可選）');
  String get browse => _s('浏览', 'Browse', '瀏覽');
  String get stopSharing => _s('停止共享', 'Stop Sharing', '停止共享');
  String get startSharing => _s('开始共享', 'Start Sharing', '開始共享');
  String get logTitle => _s('日志', 'Logs', '日誌');
  String get logClear => _s('清空', 'Clear', '清空');
  String get deviceIdCopied => _s('设备 ID 已复制', 'Device ID copied', '裝置 ID 已複製');
  String get sessionPwdCopied =>
      _s('会话密码已复制', 'Session password copied', '工作階段密碼已複製');
  String get hostedUnsupported =>
      _s('共享本机仅支持桌面平台', 'Hosting is only supported on desktop', '共享本機僅支援桌面平台');
  String get selectCaCert => _s('选择 CA 证书文件', 'Select CA Certificate', '選擇 CA 憑證檔案');

  // ── chat_panel.dart ───────────────────────────────────────────────────────────
  String get chat => _s('聊天', 'Chat', '聊天');
  String get waitingForConnection =>
      _s('等待连接', 'Waiting for connection', '等待連線');
  String get sendMessageHint => _s('发消息给对方', 'Message…', '傳送訊息給對方');
  String get copied => _s('已复制', 'Copied', '已複製');
  String get copyAll => _s('复制全部', 'Copy All', '複製全部');
  String get sendFile => _s('发送文件', 'Send File', '傳送檔案');
  String get waitingConnection => _s('等待连接…', 'Waiting…', '等待連線…');
  String get messageInputHint => _s('发消息…', 'Message…', '傳送訊息…');
  String get file => _s('文件', 'File', '檔案');
  String get openFile => _s('打开文件', 'Open', '開啟檔案');
  String get transferFailed => _s('传输失败', 'Transfer Failed', '傳輸失敗');

  // ── remote_screen.dart ───────────────────────────────────────────────────────
  String get connectingWebRTC =>
      _s('正在建立连接…', 'Connecting…', '正在建立連線…');
  String get back => _s('返回', 'Back', '返回');
  String get remoteDesktop => _s('远程桌面', 'Remote Desktop', '遠程桌面');
  String get restore => _s('复原', 'Restore', '還原');
  String get keyboard => _s('键盘', 'Keyboard', 'Keyboard');
  String get paste => _s('粘贴', 'Paste', '貼上');
  String get hide => _s('隐藏', 'Hide', '隱藏');
  String get disconnect => _s('断开', 'Disconnect', '中斷');

  // ── remote_screen_desktop.dart ────────────────────────────────────────────────
  String get connectingWebRTCDesktop =>
      _s('正在建立 WebRTC 连接…', 'Establishing WebRTC connection…', '正在建立 WebRTC 連線…');
  String get showToolbar => _s('显示工具栏', 'Show Toolbar', '顯示工具列');
  String get collapse => _s('收起', 'Collapse', '收起');
  String get controlPanel => _s('控制面板', 'Controls', '控制面板');

  // ── remote_session.dart errors ───────────────────────────────────────────────
  String get errTimeout =>
      _s('连接超时，请检查服务器地址是否正确',
          'Connection timed out. Check server URL.',
          '連線逾時，請檢查伺服器地址是否正確');
  String get errClosed =>
      _s('连接被服务器关闭，请检查服务器地址和设备 ID',
          'Connection closed by server. Check server URL and device ID.',
          '連線被伺服器關閉，請檢查伺服器地址和裝置 ID');
  String get errWrongPwd =>
      _s('会话密码错误，请重新输入', 'Wrong session password.', '工作階段密碼錯誤，請重新輸入');
  String get errDeviceOffline =>
      _s('设备不在线，请确认设备 ID', 'Device offline. Check device ID.', '裝置不在線，請確認裝置 ID');
  String get errAuthFailed =>
      _s('认证失败，请检查设备密钥', 'Authentication failed. Check device token.', '認證失敗，請檢查裝置密鑰');
  String get errUnknown =>
      _s('服务器返回未知错误', 'Unknown server error.', '伺服器回傳未知錯誤');

  // ── Session error code → message ──────────────────────────────────────────────
  String sessionError(String code) {
    switch (code) {
      case 'ERR_TIMEOUT':
        return errTimeout;
      case 'ERR_CLOSED':
        return errClosed;
      case 'ERR_WRONG_PWD':
        return errWrongPwd;
      case 'ERR_DEVICE_OFFLINE':
        return errDeviceOffline;
      case 'ERR_AUTH_FAILED':
        return errAuthFailed;
      case 'ERR_UNKNOWN':
        return errUnknown;
      default:
        return code;
    }
  }

  // ── Language names ────────────────────────────────────────────────────────────
  String get langZh => _s('简体中文', '简体中文', '简体中文');
  String get langEn => _s('English', 'English', 'English');
  String get langZhTW => _s('繁體中文', '繁體中文', '繁體中文');
}

// ── Delegate ──────────────────────────────────────────────────────────────────

class _Delegate extends LocalizationsDelegate<AppLocalizations> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) {
    if (locale.languageCode == 'en') return true;
    if (locale.languageCode == 'zh') return true;
    return false;
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_Delegate old) => false;
}
