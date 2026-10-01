
final class SettingsDescriptions {
  SettingsDescriptions._();
  static const playbackTime = '在进度条后显示已播放与总时长';

  static const overview = '把它调成你喜欢的样子';

  
  static const componentSize = '小一点更轻巧，大一点更醒目';
  static String customComponentSize(int percent) => '拖动边框，改变大小 · 当前 $percent%';
  static const alwaysOnTop = '把它始终留在屏幕上';
  static const mousePassthrough = '绝对不会影响你的游戏操作';

  
  static const colorTheme = '我们拥有绝佳的自研色彩引擎';
  static const settingsNavigationShape = '支持谷歌Material Design样式';
  static const oled = '针对OLED屏幕优化';
  static const glow = '让封面铺满整个组件';
  static const glowMode = '选择你的色彩引擎';
  static const coverParallax = '3D大封面，用过都说好';
  static const rightCoverDarkening = '让它安静一点，把主角留给左边';
  static const rightCoverFadeLength = '拉长一点，更自然地融进背景';
  static const rightCoverFadeLinked = '一起调，或给横向、纵向各留一条滑块';
  static const rightCoverBlur = '保留轮廓，少一点抢眼的细节';
  static const progressAutoContrast = '保持进度条清晰可见，减少背景干扰';
  static const spectrum = '音频可视化会在组件上方显示';
  static const performanceMonitor = '采集CPU，GPU和帧率数据';
  static String performanceFpsStatus(String status) => switch (status) {
    'selectProcess' => '选择正在运行的游戏，重启后也会自动匹配',
    'waitingProcess' => '等你打开这个程序，就会继续采集',
    'starting' => '正在连接所选程序',
    'capturing' => '从程序提交的画面中读取帧率',
    'permissionDenied' => 'Windows 暂未允许读取帧事件，可在下面授权后重试',
    'missingHelper' => '缺少帧率采集组件，请保留完整的 runtime 文件夹',
    'unavailable' => '当前环境不支持 Windows 帧率采集',
    _ => '暂时无法读取帧率，可重启组件后重试',
  };

  
  static const sourceAutomatic = '选择你想要';
  static const sourceSelected = '仅展示选中播放器的音频，不混入其他程序的声音';
  static const playbackControls = '变为纯粹的音乐挂件';
  static const trackTextAnimations = '换歌时，歌名和歌手只演一遍';
  static const trackTextTransition = '选一个你喜欢的出场方式';
  static const trackTextAnimationsLinked = '打开时，旧歌退场会与新歌进场相呼应';
  static const trackTextExitTransition = '让上一首也好好告别';
  static const showPlaylist = '只在歌曲快结束时显示下一首';
  static const nextUpLead = '自定义什么时候显示预告';
  static const playlistFileEmpty = '选个歌单文件，让下一首预告有迹可循';
  static const qqPlaylistEmpty = '贴上歌单分享链接或 ID';
  static String qqPlaylistConnected(String id) => '已连接歌单 $id，下一首会按顺序推测';
  static const qqPlaylistDialog = '贴上歌单分享链接或 ID，短链会自动识别。预告按歌单顺序推算，不代表当前播放队列';

  
  static const showLyrics = '这是一个神秘的歌词显示';
  static const lyricsTransition = '新的一句会这样来到眼前';
  static const lyricsLinkAnimations = '打开时，上一句离开和下一句进入会使用同一种风格';
  static const lyricsExitTransition = '上一句离开时，也可以有自己的节奏';
  static const lyricsProviderLrclib = '会用歌名、歌手和时长，在线找一找歌词';
  static const lyricsProviderLocal = '只在你选的文件夹里找，不用在线查询';
  static const lyricsProviderQqMusic = '先试试 QQ 音乐；找不到时会回到 LRCLIB';
  static const localLyricsEmpty = '把 .lrc 放进文件夹，按“歌手 - 歌名”命名更容易找到';
  static const lyricsUseThemeFont = '歌词用同一套字体，大小和粗细仍然自己调';
  static const lyricsWeight = '轻一点，或更有存在感；拖动时就能预览';
  static const lyricsSize = '调到看着舒服的大小，下面会实时预览';

  
  static const globalFont = '想换一种感觉，也可以加上自己的字体';
  static const titleWeight = '让歌名轻一点或更醒目，拖动就能看到';
  static const artistWeight = '歌手名不必和歌名一样抢眼';
}
