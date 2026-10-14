# Local AI portraits for Sovereign's Eye

This folder turns every villager's data into a painted character-card portrait on your own computer.

- It is **separate from the game**: Godot ignores it (`.gdignore`) and it is never included in the downloads.
- The game itself never runs AI.
- When a portrait exists, the card shows it. Otherwise it shows the live 3D portrait.

## Which tool, and why

You downloaded four tools into `outputs/Sovereigns-Eye-AI-Tools`. That folder is on your computer, so I reviewed each tool from its official project information:

| Tool | Verdict | Why |
|---|---|---|
| **ComfyUI** | ✅ **Use this** | Official, native **FLUX.2 [klein]** support (templates since 2026-01-16). A local HTTP API, so one script can paint a whole village. One workflow file makes results reproducible. |
| Fooocus | ❌ | In long-term-support (bug fixes only) and SDXL-only. It can't run FLUX.2, and it has no batch API. |
| AUTOMATIC1111 | ❌ | Last release v1.10.1 (Feb 2025). No native FLUX support. |
| ST-CardGen | ❌ | Builds SillyTavern chatbot character cards, not images. It calls other generators, so it adds nothing here. |

You can delete Fooocus, AUTOMATIC1111 and ST-CardGen to free disk space.

**Model: FLUX.2 [klein] 4B (distilled).**
- 4 steps per image, so it's fast.
- It renders faces and hair colors faithfully.
- The 4B model is **Apache-2.0**, so commercial use in the shipped game is fine.
- Don't use the 9B variant for game assets: its license is non-commercial.

## Models (about 15 GB, asks before downloading)

| File | Size | ComfyUI folder |
|---|---:|---|
| `flux-2-klein-4b.safetensors` | 7.22 GB | `models/diffusion_models/` |
| `qwen_3_4b.safetensors` | 7.49 GB | `models/text_encoders/` |
| `flux2-vae.safetensors` | 0.32 GB | `models/vae/` |

```sh
python download_models.py --comfyui "PATH/TO/ComfyUI"
```

The script lists the files and totals, and downloads nothing until you type `yes`. You can also download the same files yourself from Comfy-Org's Hugging Face pages, which are linked in ComfyUI's FLUX.2 [klein] template.

**Hardware.** An NVIDIA GPU with 8 GB+ VRAM works well. ComfyUI moves parts of the model to system RAM when VRAM is short, and Apple Silicon Macs work too, but both are slower. ComfyUI also offers smaller fp8 versions of the diffusion model; pass that file name with `--unet`.

## Paint a village

1. **Update ComfyUI** to a 2026 build. FLUX.2 [klein] needs ComfyUI from 2026-01-16 or later. Then start it.
2. **Play the game.** Starting or loading a village writes all prompts to `…/Godot/app_userdata/Sovereign's Eye/portraits/<world seed>/prompts.json`.
3. **Test with a few villagers:**
   ```sh
   python generate_portraits.py --limit 3
   ```
4. **Paint everyone else:** run it again without `--limit`. Portraits that already exist are skipped.
5. **Check the result.** Open any villager's card in the game. Their portrait is now the painting.

Useful options:
- `--only 3,17`: specific villagers by id.
- `--overwrite`: repaint everything.
- `--dry-run`: print the prompts without generating.
- `--prompts FILE`: use another village.
- `--server URL`: ComfyUI on another machine.

## How portraits stay consistent

**The same settings for every portrait.**
- **One style for everyone.** The style text and negative prompt live in `data/art_style.json` (`portrait`). Change the look there, then repaint with `--overwrite` so the whole village matches.
- **One recipe.** Same model, sampler, 4 steps and 768×960 size every time (`workflows/portrait_flux2_klein_4b_distilled_api.json`).
- **A fixed seed per villager.** It comes from the world seed and the character id. Re-running paints the same face, and two villages never share portraits.

**Prompts come from the villager's data.**
- Age and gender, job, and named skin, hair and eye colors.
- Hair style and beard, face shape, nose, freckles and scars.
- Outfit colors, headwear and current mood.
- Children inherit face traits from their parents, so families resemble each other.

**Next step, if the faces drift too much.** Use the FLUX.2 [klein] *image edit* workflow with one approved "style reference" portrait, so every new portrait is painted against it. Ask me and I'll add it as a second workflow.

## Using your own ComfyUI workflow

Build it in ComfyUI, then use **Workflow → Export (API)** and pass it with `--workflow my_workflow.json`. The script patches nodes by type:

- the positive and negative `CLIPTextEncode`;
- the seed in `RandomNoise` or `KSampler`;
- the size in the latent and scheduler nodes;
- the `SaveImage` prefix.

So most text-to-image workflows work without edits.

## Publishing note

Steam requires disclosing AI-generated content on the store page. Portraits made with this tool before release count as pre-generated AI content.
