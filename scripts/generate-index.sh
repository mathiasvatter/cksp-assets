#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

out_dir="assets/video"

html_escape() {
  printf '%s' "$1" \
    | sed -e 's/&/\&amp;/g' \
          -e 's/</\&lt;/g' \
          -e 's/>/\&gt;/g' \
          -e 's/"/\&quot;/g' \
          -e "s/'/\&#39;/g"
}

file_size() {
  wc -c < "$1" | tr -d ' '
}

human_size() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1048576)   printf "%.1f MB", b / 1048576;
    else if (b >= 1024) printf "%.0f KB", b / 1024;
    else                printf "%d B", b;
  }'
}

# Abgeleitete Videos tauchen nicht als eigene Karten auf - sie haengen als
# Alternativformat an der Karte ihres Quell-GIFs.
assets=()
while IFS= read -r path; do
  [[ "$path" == "$out_dir"/* ]] && continue
  assets+=("$path")
done < <(find assets -type f | sort)

{
  cat <<'HTML_HEAD'
<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>CKSP Assets</title>
  <style>
    :root {
      --bg: #f7f7f2;
      --panel: #ffffff;
      --text: #1b1b1b;
      --muted: #666666;
      --line: #d8d8cf;
      --accent: #0f766e;
      --accent-strong: #115e59;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 32px 18px 64px;
      font-family: "Avenir Next", "Segoe UI", sans-serif;
      color: var(--text);
      background: radial-gradient(circle at top right, #e9f5f3, var(--bg) 55%);
    }
    .wrap {
      max-width: 1100px;
      margin: 0 auto;
    }
    h1 {
      margin: 0 0 8px;
      font-size: clamp(1.7rem, 2.5vw, 2.4rem);
    }
    .meta {
      margin: 0 0 18px;
      color: var(--muted);
      font-size: 0.95rem;
    }
    .globals {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      align-items: center;
      margin: 0 0 24px;
      font-size: 0.9rem;
      color: var(--muted);
    }
    .grid {
      display: grid;
      gap: 14px;
      grid-template-columns: repeat(auto-fill, minmax(290px, 1fr));
    }
    .asset {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 12px;
      box-shadow: 0 10px 24px rgba(0, 0, 0, 0.04);
      display: grid;
      gap: 10px;
      align-content: start;
    }
    .path {
      margin: 0;
      font-size: 0.88rem;
      color: var(--muted);
      word-break: break-all;
    }
    .url {
      font-size: 0.85rem;
      word-break: break-all;
      color: var(--accent-strong);
      text-decoration: none;
    }
    .url:hover { text-decoration: underline; }
    .preview {
      width: 100%;
      max-height: 280px;
      object-fit: contain;
      border-radius: 8px;
      border: 1px solid var(--line);
      background: #fafaf7;
      display: block;
    }
    .preview[hidden] { display: none; }
    .formats {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
    }
    .fmt {
      background: transparent;
      color: var(--muted);
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 4px 11px;
      font-size: 0.8rem;
      font-weight: 600;
      cursor: pointer;
    }
    .fmt:hover { border-color: var(--accent); color: var(--accent-strong); }
    .fmt[aria-pressed="true"] {
      background: var(--accent);
      border-color: var(--accent);
      color: #fff;
    }
    .fmt .size {
      font-weight: 400;
      opacity: 0.75;
      margin-left: 5px;
    }
    .actions {
      display: flex;
      gap: 8px;
      align-items: center;
    }
    button.copy, button.global-fmt {
      border: 0;
      border-radius: 9px;
      padding: 8px 12px;
      background: var(--accent);
      color: white;
      font-weight: 600;
      cursor: pointer;
    }
    button.copy:hover, button.global-fmt:hover { background: var(--accent-strong); }
    button.global-fmt {
      background: transparent;
      color: var(--accent-strong);
      border: 1px solid var(--line);
    }
    button.global-fmt:hover { background: #ffffff; border-color: var(--accent); }
    .status {
      font-size: 0.82rem;
      color: var(--muted);
      min-height: 1em;
    }
    .empty {
      background: #fff7ed;
      border: 1px solid #fed7aa;
      color: #9a3412;
      border-radius: 10px;
      padding: 10px 12px;
    }
  </style>
</head>
<body>
  <main class="wrap">
    <h1>CKSP Assets</h1>
    <p class="meta">Direkte Links zum Posten auf Foren und Chats.</p>
    <div class="globals">
      <span>Alle Animationen umschalten:</span>
      <button type="button" class="global-fmt" data-fmt="gif">GIF</button>
      <button type="button" class="global-fmt" data-fmt="mp4">MP4</button>
    </div>
HTML_HEAD

  if [[ ${#assets[@]} -eq 0 ]]; then
    cat <<'HTML_EMPTY'
    <div class="empty">Keine Dateien unter <code>assets/</code> gefunden.</div>
HTML_EMPTY
  else
    echo '    <section class="grid">'
    for path in "${assets[@]}"; do
      escaped_path="$(html_escape "$path")"

      # Passendes MP4 aus dem Konvertierungslauf suchen
      mp4=""
      poster=""
      # Kein ${var,,} - macOS liefert nur Bash 3.2 aus
      if [[ "$path" == *.gif || "$path" == *.GIF ]]; then
        rel="${path#assets/}"
        candidate="$out_dir/${rel%.*}.mp4"
        if [[ -f "$candidate" ]]; then
          mp4="$candidate"
          [[ -f "$out_dir/${rel%.*}.jpg" ]] && poster="$out_dir/${rel%.*}.jpg"
        fi
      fi

      if [[ -n "$mp4" ]]; then
        cat <<HTML_ITEM
      <article class="asset" data-path="$escaped_path" data-mp4="$(html_escape "$mp4")" data-poster="$(html_escape "$poster")" data-format="mp4">
        <p class="path">$escaped_path</p>
        <div class="formats">
          <button type="button" class="fmt" data-fmt="gif" aria-pressed="false">GIF <span class="size">$(human_size "$(file_size "$path")")</span></button>
          <button type="button" class="fmt" data-fmt="mp4" aria-pressed="true">MP4 <span class="size">$(human_size "$(file_size "$mp4")")</span></button>
        </div>
        <a class="url" target="_blank" rel="noopener noreferrer"></a>
        <img class="preview preview-gif" loading="lazy" alt="$escaped_path" hidden>
        <video class="preview preview-mp4" autoplay muted loop playsinline preload="none"></video>
        <div class="actions">
          <button type="button" class="copy">URL kopieren</button>
          <span class="status"></span>
        </div>
      </article>
HTML_ITEM
      else
        cat <<HTML_ITEM
      <article class="asset" data-path="$escaped_path">
        <p class="path">$escaped_path</p>
        <a class="url" target="_blank" rel="noopener noreferrer"></a>
        <img class="preview preview-gif" loading="lazy" alt="$escaped_path">
        <div class="actions">
          <button type="button" class="copy">URL kopieren</button>
          <span class="status"></span>
        </div>
      </article>
HTML_ITEM
      fi
    done
    echo '    </section>'
  fi

  cat <<'HTML_TAIL'
  </main>
  <script>
    (function () {
      function encodeAssetPath(path) {
        return encodeURI(path).replace(/%2F/g, '/');
      }

      function absoluteUrl(path) {
        return new URL(encodeAssetPath(path), document.baseURI).href;
      }

      async function copyText(text) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(text);
          return;
        }

        const ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
      }

      const cards = [];

      // Ohne das wuerden beim Laden saemtliche Videos gleichzeitig starten.
      // So laedt und spielt nur, was tatsaechlich im Blickfeld ist.
      const videoObserver = ('IntersectionObserver' in window)
        ? new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
              const v = entry.target;
              if (entry.isIntersecting) {
                if (!v.src && v.dataset.src) v.src = v.dataset.src;
                const p = v.play();
                if (p && p.catch) p.catch(() => {});
              } else {
                v.pause();
              }
            });
          }, { rootMargin: '200px' })
        : null;

      document.querySelectorAll('.asset').forEach((card) => {
        const gifUrl = absoluteUrl(card.dataset.path);
        const mp4Url = card.dataset.mp4 ? absoluteUrl(card.dataset.mp4) : '';

        const link = card.querySelector('.url');
        const img = card.querySelector('.preview-gif');
        const video = card.querySelector('.preview-mp4');
        const button = card.querySelector('.copy');
        const status = card.querySelector('.status');

        // Ohne MP4-Variante bleibt es bei der schlichten Bildkarte
        if (!mp4Url) {
          link.href = gifUrl;
          link.textContent = gifUrl;
          img.src = gifUrl;
          button.addEventListener('click', () => copyWithFeedback(gifUrl, status));
          return;
        }

        if (card.dataset.poster) {
          video.poster = absoluteUrl(card.dataset.poster);
        }

        function apply(format) {
          const isMp4 = format === 'mp4';
          card.dataset.format = format;

          const url = isMp4 ? mp4Url : gifUrl;
          link.href = url;
          link.textContent = url;

          card.querySelectorAll('.fmt').forEach((btn) => {
            btn.setAttribute('aria-pressed', String(btn.dataset.fmt === format));
          });

          img.hidden = isMp4;
          video.hidden = !isMp4;

          // Quellen erst setzen, wenn das Format wirklich sichtbar ist,
          // damit die Seite nicht beide Varianten laedt.
          if (isMp4) {
            video.dataset.src = mp4Url;
            if (videoObserver) {
              videoObserver.observe(video);
            } else if (!video.src) {
              video.src = mp4Url;
              const played = video.play();
              if (played && played.catch) played.catch(() => {});
            }
          } else {
            if (videoObserver) videoObserver.unobserve(video);
            video.pause();
            if (!img.src) img.src = gifUrl;
          }
        }

        card.querySelectorAll('.fmt').forEach((btn) => {
          btn.addEventListener('click', () => apply(btn.dataset.fmt));
        });

        button.addEventListener('click', () => {
          copyWithFeedback(card.dataset.format === 'mp4' ? mp4Url : gifUrl, status);
        });

        cards.push(apply);
        apply(card.dataset.format || 'mp4');
      });

      async function copyWithFeedback(url, status) {
        try {
          await copyText(url);
          status.textContent = 'Kopiert';
          setTimeout(() => { status.textContent = ''; }, 1400);
        } catch (err) {
          status.textContent = 'Konnte nicht kopieren';
        }
      }

      document.querySelectorAll('.global-fmt').forEach((btn) => {
        btn.addEventListener('click', () => {
          cards.forEach((apply) => apply(btn.dataset.fmt));
        });
      });
    })();
  </script>
</body>
</html>
HTML_TAIL
} > index.html

echo "Generated index.html with ${#assets[@]} asset(s)."
