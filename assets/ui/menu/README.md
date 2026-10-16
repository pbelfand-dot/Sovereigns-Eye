# Title screen art

The title screen (`scripts/ui/main_menu.gd`) uses two images from this folder
when they are here, and falls back to a warm gradient and the game's icon when
they are not:

| File | What | Size | Notes |
| --- | --- | --- | --- |
| `key_art.jpg` | The key art behind the menu | 2560 × 1440 (16:9), JPEG quality ~88 | Covers the screen (cropped to fit), drifts in slowly; the left side is darkened for the menu column, so keep the subject in the right two-thirds |
| `emblem.png` | The heraldic emblem above the title | 512 × 512, PNG with transparency | Shown at 112 px |

Both are made with Higgsfield (GPT Image 2.5, high quality, 4K for the key
art, 2K with a transparent background for the emblem), then downscaled.

## Prompts

**Key art** (16:9):

> Painterly key art for a medieval village-building strategy game's title screen, wide cinematic landscape, no text. Late golden-hour light over a small twelfth-century English village in a green valley: a grey stone chapel with a square bell tower, a red clay-tile pyramid roof and a small iron cross on top, a few thatched cottages and timber-framed houses with red tile roofs, a cobbled market square with a stone well, colourful heraldic banners on poles, patchwork fields edged with wattle fences, haystacks, a dirt road winding through, a dark forest edge and soft blue hills behind. On the right, in the foreground on a grassy rise, a young noble heir stands seen from behind at three-quarters, in a long deep royal-blue cloak, looking down over the village; a faint warm golden light glints at the edge of their eye. Warm low sun from the right, long shadows, gentle haze, a few birds. The left third of the frame is calm and darker: open dusky sky and shadowed meadow, uncluttered, to leave room for a menu. Rich oil-painting brushwork, slightly stylized storybook realism, warm greens, honey gold and deep blue palette, high detail, no text, no logo, no watermark, no border.

**Emblem** (1:1, transparent background):

> A heraldic game emblem, front view, centered, isolated on a fully transparent background. A gilded open human eye with a deep blue iris and a tiny gold glint, set in the middle of a radiant sunburst of fine gold rays, all on a heater shield of dark navy blue enamel with a thin raised gold border, a small simple gold crown above the shield. Medieval illuminated-manuscript and goldsmith style, crisp clean edges, subtle bevel and metallic sheen, symmetrical, no text, no letters, no background, no shadow.

A dusk variant of the key art and a round seal variant of the emblem were
made from the same brief; pick whichever reads best behind the menu.

## Rights

Images generated with Higgsfield are used under the Higgsfield account
holder's plan terms; keep that plan's commercial-use terms in mind before
shipping. They are not CC0 like the game's 3D families.
