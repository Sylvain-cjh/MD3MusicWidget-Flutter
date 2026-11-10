# 封面动态配色（Monet）

- 参考 [Google Material Color Utilities 取色指南](https://github.com/material-foundation/material-color-utilities/blob/main/dev_guide/extracting_colors.md)：从封面按比例取一份最长边不超过 128 像素的样本，以 ARGB 进入 Celebi 量化，在后台 isolate 运行 HCT 评分。同一封面可复用种子色，切换明暗或主题风格不重新采样。
- 参考 [Android 17 CDD §3.8.6](https://source.android.com/docs/compatibility/17/android-17-cdd#386_themes)：种子采用 CAM16 色度门槛；封面缺少合格颜色时用 `#1B6EF3`。Windows 挂件使用歌曲封面，而非 Android 系统壁纸或系统调色板。
- 挂件保留自己的封面处理：透明、近白和近黑背景不作为主体颜色；极少量的彩色噪点不能决定主题；白色面积超过 55% 时保留原有的轻微对比度补偿。
- 色彩主题保留柔和、艳丽、真实，新增可选的「表现力」（Expressive），默认仍为柔和（Tonal Spot）。UIA 气泡使用 Material 3 推荐的强调容器/文字角色 `tertiaryContainer` / `onTertiaryContainer`，并在明暗动画中校验文字对比度。

Flutter 3.44.4 的 SDK 固定 `material_color_utilities: 0.13.0`，本次没有用依赖覆盖替换 SDK 内部库。[0.13.1 的变更](https://pub.dev/packages/material_color_utilities/changelog#0131---2026-08-10)主要是 CAM16 色相角归一化修正。本次升级的是挂件的采样、排名和颜色角色接入，不宣称逐色复刻 Android 17 系统主题。
