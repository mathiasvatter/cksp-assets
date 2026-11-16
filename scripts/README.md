# From screen recording to a forum-ready GIF

How a screen recording becomes an asset under
`https://mathiasvatter.github.io/cksp-assets/assets/`, small enough for a forum post, with
a caption bar that says what is happening.

## 1. Record

Record in the editor at the size you want to show. Things that keep the GIF small:

* **Crop tightly** to the code. Every pixel that moves costs bytes. Scrolling, the minimap
  and zoom transitions are the expensive parts.
* **A dark theme with a flat background** (VS Code Dark Modern, `#1f1f1f`) compresses much
  better than a background with a gradient or transparency.
* **Pause on the result.** Frames that do not change are nearly free, so a pause costs
  almost nothing and gives the viewer time to read.
* Keep it under ~30 seconds. Anything longer belongs on YouTube (see the marketing
  playbook).

## 2. Write the captions

One file per recording in `captions/`, named like the asset: `captions/<name>.captions`.
Each line has a start time in seconds and the text. A caption stays until the next one
starts. `#` lines are comments.

```
# start (s)  caption
0     Hover over any reference to see its declaration
9.5   Hold Cmd to preview the whole declaration
12    Hover over any reference to see its declaration
17.5  Inlay hints show the type the compiler inferred
```

To find the times, make a contact sheet with one timestamped frame per second:

```sh
ffmpeg -v error -i recording.mp4 \
  -vf "fps=1,scale=326:-1,drawtext=fontfile=/System/Library/Fonts/Helvetica.ttc:text='%{pts\:hms}':x=4:y=4:fontsize=20:fontcolor=yellow:box=1:boxcolor=black,tile=6x6" \
  -frames:v 1 sheet.png
```

Captions should say what the viewer is looking at, from their side: "Hold Cmd to preview
the declaration", not "LSP hover provider". Keep each one short enough to read in the time
it is shown.

## 3. Convert

```sh
scripts/mp4-to-gif.sh -c captions/<name>.captions ~/Downloads/<name>.mp4 assets/<name>.gif
```

This adds a bar above the video in the editor background colour and writes each caption
centred into it. The defaults suit editor screencasts:

| | default | why |
|---|---|---|
| `GIF_FPS` | 10 | Enough for cursor movement and typing. |
| `GIF_COLORS` | 32 | Code on a flat background needs few colours. |
| `GIF_DITHER` | none | Dithering adds noise to flat areas, and noise does not compress. |
| `GIF_WIDTH` | source width | Set e.g. `GIF_WIDTH=720` to shrink. |

Frames identical to the previous one are dropped and become a longer frame delay instead.
Without `-c`, the script converts without a caption bar.

What to expect: the 32-second, 978×448 `lsp-type-hints-hover` recording came out at
**5.6 MB** with captions. The same recording exported from Adobe Express was 12 MB. With
`GIF_WIDTH=720 GIF_FPS=8` it is 2.8 MB. The caption bar itself costs next to nothing.

Check a frame before publishing. The caption bar and text should be sharp:

```sh
ffmpeg -v error -ss 10 -i assets/<name>.gif -frames:v 1 check.png
```

If the text looks blotchy, raise `GIF_COLORS` to 64. That costs about 20 % (6.8 instead
of 5.6 MB for the recording above).

## 4. Publish

```sh
scripts/assetpush.sh assets/<name>.gif "add <name>"
```

The script commits, pushes, prints the URL and copies it to the clipboard. The Pages
workflow then also builds `assets/video/<name>.mp4` and a poster frame from every GIF
(`build-video.sh`), for places that can play video instead.

Commit the captions file too (`git add captions/<name>.captions`), so the GIF can be
rebuilt with different text later. It lives outside `assets/`, so it is not published.

## Other scripts

* `compress-video.sh` recompresses a video to H.264 at the same resolution, for an MP4
  asset.
* `build-video.sh` and `generate-index.sh` run in the Pages workflow; no need to call them
  by hand.
