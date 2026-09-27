
final class SettingsDescriptions {
  SettingsDescriptions._();

  static const overview = '把音乐角落调成你喜欢的样子';

  
  static const componentSize = '小一点更轻巧，大一点更醒目；也能自己调整。';
  static String customComponentSize(int percent) =>
      '拖动边框就好，比例会保持不变 · 当前 $percent%';
  static const alwaysOnTop = '切到别的窗口，它也会留在屏幕上。';
  static const mousePassthrough = '想点到后面的窗口时打开；点托盘图标就能恢复。';

  
  static const colorTheme = '喜欢柔和一点，还是想让封面的颜色更鲜明？';
  static const settingsNavigationShape = '上面的滑块和悬停效果，会一起换成你选的形状。';
  static const oled = '让背景彻底变黑，夜里看更干净。';
  static const glow = '让封面的颜色轻轻铺满整个组件。';
  static const glowMode = '想让颜色向下流淌，还是铺成一整片？';
  static const coverParallax = '鼠标靠近时，封面会轻轻跟着动。';
  static const progressAutoContrast = '背景忽明忽暗时，进度和频谱也能看得清。';
  static const spectrum = '打开后会留在组件下方，跟着音乐起伏。';

  
  static const sourceAutomatic = '会跟着正在播放的程序走。';
  static const sourceSelected = '只看这一个播放器，不混入其他程序的声音。';
  static const playbackControls = '只想展示歌曲？关掉后，三个按钮就会收起来。';
  static const showPlaylist = '只在歌曲快结束时露出下一首，平时不显示歌单。';
  static const nextUpLead = '决定距离结束还有多久时，预告会出现。';
  static const playlistFileEmpty = '选个歌单文件，让下一首预告有迹可循。';
  static const qqPlaylistEmpty = '贴上歌单分享链接或 ID，短链也可以。';
  static String qqPlaylistConnected(String id) => '已连接歌单 $id，下一首会按顺序推测。';
  static const qqPlaylistDialog = '贴上歌单分享链接或 ID，短链会自动识别。预告按歌单顺序推算，不代表当前播放队列。';

  
  static const showLyrics = '想跟着唱时打开，歌词会出现在播放器下方。';
  static const lyricsTransition = '挑一种看着舒服的换行方式；不想动也可以关掉。';
  static const lyricsProviderLrclib = '会用歌名、歌手和时长，在线找一找歌词。';
  static const lyricsProviderLocal = '只在你选的文件夹里找，不用在线查询。';
  static const lyricsProviderQqMusic = '先试试 QQ 音乐；找不到时会回到 LRCLIB。';
  static const localLyricsEmpty = '把 .lrc 放进文件夹，按“歌手 - 歌名”命名更容易找到。';
  static const lyricsUseThemeFont = '歌词用同一套字体，大小和粗细仍然自己调。';
  static const lyricsWeight = '轻一点，或更有存在感；拖动时就能预览。';
  static const lyricsSize = '调到看着舒服的大小，下面会实时预览。';

  
  static const globalFont = '想换一种感觉，也可以加上自己的字体。';
  static const titleWeight = '让歌名轻一点或更醒目，拖动就能看到。';
  static const artistWeight = '歌手名不必和歌名一样抢眼。';
}
