# 三元重戟首页主视觉

- 原始图标：从本机官方 `game/dota/pak01_dir.vpk` 中提取 `panorama/images/items/trident_png.vtex_c`，CRC32 `84e0f406`。
- 原始图像：`trident-original.png`，88×64；由纹理的原生 BGRA8888 数据解码，不作造型编辑。
- 高清重绘：内置 ImageGen，根据原始图标进行参考重绘，并非无损恢复原图中不存在的细节。
- 站点资源：`../dist/assets/trident-hero.png`。只用于网页，不替换游戏资源。

## 重绘提示词

Use case: stylized-concept, reference-guided high-resolution restoration of an existing game item icon for a Dota 2 mod website hero. Input image is the ORIGINAL Trident item icon extracted from the user's locally installed Dota 2 game (88x64). Reimagine it at extremely high resolution while faithfully preserving its recognizable weapon silhouette, blade geometry, dark metallic body, silver beveled edges, and vivid electric ice-blue/cyan magical outlines. It is an ornate fantasy trident / three-pronged bladed weapon, with a long shaft running diagonally from lower-left toward upper-right, a sculpted central silver blade and two curling outward side blades, intricate blackened steel surfaces. Preserve the reference object identity, do not turn it into a generic gold Poseidon spear or a collection of crossed swords. Single hero object filling most of a wide landscape image, entire head visible without cropping, handle extending to lower-left; focus head in the upper-right-center, leaving modest surrounding dark space. The site has a dark charcoal Dota-like metal theme. Nearly black midnight smoky background with a restrained blue arcane aura around the blades and very subtle airborne particles, dramatic rim light, realistic polished silver/black metal with finely resolved engravings and physically convincing highlights, cinematic AAA fantasy item illustration. Crisp readable silhouette, substantial material detail, beautiful but restrained contrast, no UI, no words, no numbers, no logos, no border, no other weapons, no characters. Landscape composition suitable for a large website hero.
