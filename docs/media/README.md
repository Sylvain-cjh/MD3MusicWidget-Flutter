# README 预览素材

- `player-horizontal.png`：横版组件。
- `player-vertical.png`：竖版组件。
- `settings.png`：设置页。
- `glass-switch.png`：深色设置中，液态玻璃开关静止时的 Flutter 渲染细节。
- `readme-hero.svg`：README 专用紫色与薄荷绿唱片插画，不是应用截图或应用图标。
- `tell-your-world.jpg`：预览中使用的《Tell Your World EP》封面。

图片由项目现有 Flutter 组件在隔离 Widget 环境中渲染，使用内置 MiSans 字体与《Tell Your World》曲目信息。播放位置、歌词定位与频谱输入仅用于展示布局，不是真实播放记录，也不代表实际歌词时间轴。不是桌面录屏或真实播放器采集，不包含个人桌面、账号或聊天信息；也不是帧率、设备兼容性或分层质量的验证结果。

## 曲目与素材来源

- 曲目：**Tell Your World**；艺人：**livetune feat. 初音ミク**。参见 [TOY'S FACTORY 官方唱片页](https://www.toysfactory.co.jp/sp/artist/livetune/disco/896) 与 [Apple Music 曲目页](https://music.apple.com/jp/album/tell-your-world-feat-%E5%88%9D%E9%9F%B3%E3%83%9F%E3%82%AF/505898719?i=505898722)。
- 封面：使用 Apple Music [封面预览图](https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/0d/6f/5c/0d6f5cd0-af35-4aa2-56cb-69644e55da18/mzi.lfrvelge.jpg/600x600bb.jpg)，保留原图；仅在 README 的曲目展示中使用，不替换应用 logo。
- 歌词面板使用一小段歌词作排版演示，核对来源为 [初音ミク Wiki 曲目页](https://w.atwiki.jp/hmiku/pages/19646.html)。未附带完整歌词或音频。
- 歌曲、封面及角色等权利归原权利人所有，不属于本应用的授权范围；标注来源不等同于取得再分发授权，也不代表艺人、唱片公司或角色权利人认可本项目。

文档插画、演示歌曲和封面均不是应用 logo。示例不启用模型推理、原生媒体服务、设置持久化或磁盘缓存；不会把示例数值当作真实采集数据。

开发目录中的 `tooling/readmePreview.dart` 可重新生成这些图片；该开发工具不进入程序运行负载。上述图片仅为文档展示资源，不会由挂件在运行时加载。
