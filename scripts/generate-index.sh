#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

base_url="https://mathiasvatter.github.io/cksp-assets/"

html_escape() {
  printf '%s' "$1" \
    | sed -e 's/&/\&amp;/g' \
          -e 's/</\&lt;/g' \
          -e 's/>/\&gt;/g' \
          -e 's/"/\&quot;/g' \
          -e "s/'/\&#39;/g"
}

assets=()
while IFS= read -r path; do
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
      margin: 0 0 24px;
      color: var(--muted);
      font-size: 0.95rem;
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
    }
    .actions {
      display: flex;
      gap: 8px;
      align-items: center;
    }
    button {
      border: 0;
      border-radius: 9px;
      padding: 8px 12px;
      background: var(--accent);
      color: white;
      font-weight: 600;
      cursor: pointer;
    }
    button:hover { background: var(--accent-strong); }
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
HTML_HEAD

  if [[ ${#assets[@]} -eq 0 ]]; then
    cat <<'HTML_EMPTY'
    <div class="empty">Keine Dateien unter <code>assets/</code> gefunden.</div>
HTML_EMPTY
  else
    echo '    <section class="grid">'
    for path in "${assets[@]}"; do
      escaped_path="$(html_escape "$path")"
      cat <<HTML_ITEM
      <article class="asset" data-path="$escaped_path">
        <p class="path">$escaped_path</p>
        <a class="url" target="_blank" rel="noopener noreferrer"></a>
        <img class="preview" loading="lazy" alt="$escaped_path">
        <div class="actions">
          <button type="button" class="copy">URL kopieren</button>
          <span class="status"></span>
        </div>
      </article>
HTML_ITEM
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

      document.querySelectorAll('.asset').forEach((card) => {
        const path = card.dataset.path;
        const url = new URL(encodeAssetPath(path), document.baseURI).href;

        const link = card.querySelector('.url');
        const img = card.querySelector('.preview');
        const button = card.querySelector('.copy');
        const status = card.querySelector('.status');

        link.href = url;
        link.textContent = url;
        img.src = url;

        button.addEventListener('click', async () => {
          try {
            await copyText(url);
            status.textContent = 'Kopiert';
            setTimeout(() => {
              status.textContent = '';
            }, 1400);
          } catch (err) {
            status.textContent = 'Konnte nicht kopieren';
          }
        });
      });
    })();
  </script>
</body>
</html>
HTML_TAIL
} > index.html

echo "Generated index.html with ${#assets[@]} asset(s)."
