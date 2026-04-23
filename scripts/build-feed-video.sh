#!/usr/bin/env bash
set -euo pipefail

# Build Instagram feed video (4:5, 1080x1350) for 奈良春日 鹿のや.
#
# If posts/<post>/images/ contains image files (jpg/jpeg/png), a Ken Burns
# style slideshow is produced with text captions overlaid. Otherwise a
# text-only preview video is produced so the layout and pacing can be
# reviewed before real photography is ready.
#
# Usage:
#   scripts/build-feed-video.sh [<post-dir>]
#
# Default <post-dir>: posts/2026-04-23-shisaku-ryori

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

POST_DIR="${1:-$REPO_ROOT/posts/2026-04-23-shisaku-ryori}"
if [[ "$POST_DIR" != /* ]]; then
  POST_DIR="$REPO_ROOT/$POST_DIR"
fi
IMAGES_DIR="$POST_DIR/images"
SLIDES_DIR="$POST_DIR/slides"
OUT="$POST_DIR/feed.mp4"

W=1080
H=1350
FPS=30
FONT="/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"
BG_DARK="0x0e1a12"   # 春日の杜の深緑
BG_CREAM="0xf4efe4"  # 和紙の生成り

if [[ ! -f "$FONT" ]]; then
  echo "Japanese font not found: $FONT" >&2
  echo "Install with: apt-get install -y fonts-ipafont-gothic" >&2
  exit 1
fi

shopt -s nullglob nocaseglob
IMAGES=("$IMAGES_DIR"/*.{jpg,jpeg,png})
shopt -u nocaseglob

build_text_slide() {
  # build_text_slide <text-file> <duration> <bg-color> <fg-color> <fontsize> <out>
  local textfile="$1" dur="$2" bg="$3" fg="$4" size="$5" out="$6"
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "color=c=${bg}:s=${W}x${H}:r=${FPS}:d=${dur}" \
    -vf "drawtext=textfile='${textfile}':fontfile='${FONT}':fontsize=${size}:fontcolor=${fg}:line_spacing=24:x=(w-text_w)/2:y=(h-text_h)/2:alpha='if(lt(t,0.6),t/0.6,if(gt(t,${dur}-0.6),(${dur}-t)/0.6,1))',format=yuv420p" \
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
    -movflags +faststart \
    "$out"
}

build_image_slide() {
  # build_image_slide <image> <duration> <caption-file-or-empty> <out>
  local img="$1" dur="$2" cap="$3" out="$4"
  # Subtle Ken Burns via zoompan with d=1 (1 output frame per input frame).
  # Input is -loop 1 -t DUR at FPS, so we get DUR*FPS input frames and the
  # zoom expression can ramp across them using 'on' (output frame index).
  local max_frames=$(( dur * FPS ))
  local vf="scale=${W}*2:${H}*2:force_original_aspect_ratio=increase,crop=${W}*2:${H}*2"
  vf+=",zoompan=z='min(1+0.0006*on,1.08)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=${W}x${H}:fps=${FPS}"
  if [[ -n "$cap" && -f "$cap" ]]; then
    vf+=",drawbox=x=0:y=ih-260:w=iw:h=260:color=black@0.45:t=fill"
    vf+=",drawtext=textfile='${cap}':fontfile='${FONT}':fontsize=52:fontcolor=white:line_spacing=16:x=(w-text_w)/2:y=h-text_h-80"
  fi
  vf+=",format=yuv420p"
  ffmpeg -y -hide_banner -loglevel error \
    -loop 1 -framerate "$FPS" -t "$dur" -i "$img" \
    -vf "$vf" \
    -frames:v "$max_frames" \
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -r "$FPS" \
    -movflags +faststart \
    "$out"
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

declare -a PARTS=()

if [[ ${#IMAGES[@]} -gt 0 ]]; then
  echo "Found ${#IMAGES[@]} image(s) — building photographic slideshow."
  # Opening title
  build_text_slide "$SLIDES_DIR/slide1_title.txt" 3 "$BG_DARK" "white" 96 "$TMPDIR/00_title.mp4"
  PARTS+=("$TMPDIR/00_title.mp4")

  # Up to 4 image slides, 3.5s each, captioned in rotation
  CAPTIONS=(
    "$SLIDES_DIR/slide2_location.txt"
    "$SLIDES_DIR/slide3_intro.txt"
    "$SLIDES_DIR/slide4_concept.txt"
    ""
  )
  i=0
  for img in "${IMAGES[@]}"; do
    cap="${CAPTIONS[$(( i % ${#CAPTIONS[@]} ))]}"
    out="$TMPDIR/$(printf '%02d' $((i + 10)))_img.mp4"
    build_image_slide "$img" 4 "$cap" "$out"
    PARTS+=("$out")
    i=$((i + 1))
    [[ $i -ge 4 ]] && break
  done

  # Closing
  build_text_slide "$SLIDES_DIR/slide5_closing.txt" 4 "$BG_DARK" "white" 72 "$TMPDIR/99_closing.mp4"
  PARTS+=("$TMPDIR/99_closing.mp4")
else
  echo "No images in $IMAGES_DIR — building text-only preview."
  build_text_slide "$SLIDES_DIR/slide1_title.txt"    4 "$BG_DARK"  "white"    96 "$TMPDIR/01.mp4"
  build_text_slide "$SLIDES_DIR/slide2_location.txt" 4 "$BG_DARK"  "white"    76 "$TMPDIR/02.mp4"
  build_text_slide "$SLIDES_DIR/slide3_intro.txt"    4 "$BG_CREAM" "0x0e1a12" 104 "$TMPDIR/03.mp4"
  build_text_slide "$SLIDES_DIR/slide4_concept.txt"  5 "$BG_CREAM" "0x0e1a12" 72 "$TMPDIR/04.mp4"
  build_text_slide "$SLIDES_DIR/slide5_closing.txt"  5 "$BG_DARK"  "white"    72 "$TMPDIR/05.mp4"
  PARTS=("$TMPDIR/01.mp4" "$TMPDIR/02.mp4" "$TMPDIR/03.mp4" "$TMPDIR/04.mp4" "$TMPDIR/05.mp4")
fi

# Concat
LIST="$TMPDIR/list.txt"
: > "$LIST"
for p in "${PARTS[@]}"; do
  printf "file '%s'\n" "$p" >> "$LIST"
done

# Resolve BGM: prefer post-local bgm.* then repo-root *.mp3/.m4a/.wav.
BGM=""
for candidate in "$POST_DIR"/bgm.mp3 "$POST_DIR"/bgm.m4a "$POST_DIR"/bgm.wav; do
  [[ -f "$candidate" ]] && BGM="$candidate" && break
done
if [[ -z "$BGM" ]]; then
  shopt -s nullglob
  ROOT_BGMS=("$REPO_ROOT"/*.mp3 "$REPO_ROOT"/*.m4a "$REPO_ROOT"/*.wav)
  shopt -u nullglob
  [[ ${#ROOT_BGMS[@]} -gt 0 ]] && BGM="${ROOT_BGMS[0]}"
fi

if [[ -n "$BGM" ]]; then
  echo "Using BGM: $BGM"
  # First concat video-only to a temp file so we can read total duration.
  VTMP="$TMPDIR/video_only.mp4"
  ffmpeg -y -hide_banner -loglevel error \
    -f concat -safe 0 -i "$LIST" -c copy "$VTMP"
  DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VTMP")
  FADEOUT_START=$(awk -v d="$DUR" 'BEGIN{printf "%.3f", d-1.5}')
  ffmpeg -y -hide_banner -loglevel error \
    -i "$VTMP" \
    -stream_loop -1 -i "$BGM" \
    -map 0:v:0 -map 1:a:0 \
    -af "afade=t=in:st=0:d=1.2,afade=t=out:st=${FADEOUT_START}:d=1.5,volume=0.85" \
    -shortest \
    -c:v copy \
    -c:a aac -b:a 192k -ar 48000 \
    -movflags +faststart \
    "$OUT"
else
  echo "No BGM found — using silent audio track."
  ffmpeg -y -hide_banner -loglevel error \
    -f concat -safe 0 -i "$LIST" \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=48000" \
    -shortest \
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -r "$FPS" \
    -c:a aac -b:a 128k \
    -movflags +faststart \
    "$OUT"
fi

echo "Wrote: $OUT"
ffprobe -v error -show_entries format=duration,size:stream=width,height,codec_name \
  -of default=noprint_wrappers=1 "$OUT" || true
