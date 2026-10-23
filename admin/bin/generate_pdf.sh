#!/bin/bash

# Generate index_pdf.html with folder nav in left pane and files in right pane
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The folder holding the PDF files comes from a properties file rather than
# being assumed to be the script's grandparent directory.
PROPERTIES_FILE="${GENERATE_PDF_PROPERTIES:-$SCRIPT_DIR/generate_pdf.properties}"

if [ ! -f "$PROPERTIES_FILE" ]; then
  echo "Error: properties file not found: $PROPERTIES_FILE" >&2
  exit 1
fi

# Read "key=value" from the properties file; '#' comment lines are ignored and
# surrounding whitespace plus optional quotes are stripped. Last value wins.
get_property() {
  local key_re="${1//./\\.}"
  sed -n "s/^[[:space:]]*${key_re}[[:space:]]*=[[:space:]]*//p" "$PROPERTIES_FILE" \
    | tr -d '\r' | tail -n 1 \
    | sed -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

pdf_dir="$(get_property 'pdf.dir')"
if [ -z "$pdf_dir" ]; then
  echo "Error: 'pdf.dir' is not set in $PROPERTIES_FILE" >&2
  exit 1
fi

# A relative value is resolved against the properties file's own directory.
case "$pdf_dir" in
  /*) ;;
  *) pdf_dir="$(dirname "$PROPERTIES_FILE")/$pdf_dir" ;;
esac

PDF_DIR="$(cd "$pdf_dir" 2>/dev/null && pwd)"
if [ -z "$PDF_DIR" ]; then
  echo "Error: pdf.dir is not an existing directory: $pdf_dir" >&2
  exit 1
fi

output_file="$(get_property 'output.file')"
[ -z "$output_file" ] && output_file="index_pdf.html"

OUTPUT="$PDF_DIR/$output_file"

# Collect unique folders in sorted order
# Skip hidden dirs (.Trash-*, .git), the filesystem's lost+found, and admin itself.
# Note: -mindepth would stop -prune from being evaluated at depth 1, so the depth
# filter is done below with a case glob instead.
PRUNE=( '(' -name '.*' -o -name 'lost+found' -o -name 'admin' ')' -prune -o )

mapfile -t folders < <(find "$PDF_DIR" "${PRUNE[@]}" -name "*.pdf" -print | sort | while IFS= read -r f; do
  rel="${f#$PDF_DIR/}"
  case "$rel" in */*) dirname "$rel" ;; esac
done | awk '!seen[$0]++')

first_folder="${folders[0]}"

if [ ${#folders[@]} -eq 0 ]; then
  echo "Warning: no PDF files found under $PDF_DIR; $OUTPUT left unchanged." >&2
  exit 0
fi

cat > "$OUTPUT" <<'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PDF File Index</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; }
    body { font-family: Arial, sans-serif; margin: 0; background: #f5f5f5; font-size: 1.2em; }
    /* Layout */
    .layout { display: flex; min-height: 100vh; }
    .sidebar { width: 280px; flex-shrink: 0; background: #add8e6; color: #1a1a1a; }
    .sidebar-title { padding: 24px 20px; font-size: 1.1em; font-weight: bold; letter-spacing: 0.05em; border-bottom: 1px solid #8bbfd4; }
    .nav-item { padding: 12px 20px; cursor: pointer; font-size: 0.95em; border-bottom: 1px solid #8bbfd4; transition: background 0.15s; overflow-wrap: anywhere; }
    .nav-group { padding: 10px 20px 4px 20px; font-size: 0.8em; font-weight: bold; text-transform: uppercase; letter-spacing: 0.04em; color: #2c5265; overflow-wrap: anywhere; }
    .depth-1 { padding-left: 34px; }
    .depth-2 { padding-left: 48px; }
    .depth-3 { padding-left: 62px; }
    .nav-item:hover { background: #85c1d4; }
    .nav-item.active { background: #4a8fa8; color: #fff; font-weight: bold; }
    .content { flex: 1; padding: 40px; min-width: 0; }
    /* Tables */
    .folder-panel { display: none; }
    .folder-panel h2 { color: #4a6fa5; font-size: 1em; margin: 0 0 12px 0; padding: 6px 12px; background: #e4ecf7; border-left: 4px solid #4a6fa5; border-radius: 2px; }
    table { border-collapse: collapse; width: 100%; background: #fff; box-shadow: 0 1px 4px rgba(0,0,0,0.1); }
    th { background: #4a6fa5; color: #fff; padding: 10px 14px; text-align: left; }
    td { padding: 8px 14px; border-bottom: 1px solid #ddd; }
    tr:hover td { background: #f0f4ff; }
    a { color: #2a5db0; text-decoration: none; }
    .file-path { font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; word-break: break-all; }
    a:hover { text-decoration: underline; }
    .download-btn { margin-left: 16px; padding: 2px 10px; font-size: 0.8em; background: #2e7d52; color: #fff; border: none; border-radius: 4px; cursor: pointer; }
    .download-btn:hover { background: #1a5c39; }
    /* Mobile */
    @media (max-width: 600px) {
      .layout { flex-direction: column; }
      .sidebar { width: 100%; }
      .content { padding: 20px; }
    }
  </style>
  <script>
    function showFolder(name) {
      document.querySelectorAll('.folder-panel').forEach(function(p) { p.style.display = 'none'; });
      document.querySelectorAll('.nav-item').forEach(function(i) { i.classList.remove('active'); });
      document.getElementById('folder-' + name).style.display = 'block';
      document.querySelector('.nav-item[data-folder="' + name + '"]').classList.add('active');
    }
    function downloadFile(url, filename) {
      fetch(url)
        .then(function(res) { return res.blob(); })
        .then(function(blob) {
          var objUrl = URL.createObjectURL(blob);
          var a = document.createElement('a');
          a.href = objUrl;
          a.download = filename;
          document.body.appendChild(a);
          a.click();
          document.body.removeChild(a);
          URL.revokeObjectURL(objUrl);
        });
    }
  </script>
</head>
<body>
<div class="layout">
HTMLHEAD

# Write sidebar nav
echo '  <div class="sidebar">' >> "$OUTPUT"
echo '    <div class="sidebar-title">Home</div>' >> "$OUTPUT"
declare -A emitted=()
for folder in "${folders[@]}"; do
  # Emit group labels for any ancestor dir that is not itself a nav target
  IFS='/' read -r -a segs <<< "$folder"
  prefix=""
  for ((i = 0; i < ${#segs[@]} - 1; i++)); do
    prefix="${prefix:+$prefix/}${segs[i]}"
    if [ -z "${emitted[$prefix]+x}" ]; then
      emitted[$prefix]=1
      echo "    <div class=\"nav-group depth-$i\">${segs[i]}/</div>" >> "$OUTPUT"
    fi
  done
  depth=$((${#segs[@]} - 1))
  leaf="${segs[depth]}"
  active_class=""
  [ "$folder" = "$first_folder" ] && active_class=" active"
  emitted[$folder]=1
  echo "    <div class=\"nav-item$active_class depth-$depth\" data-folder=\"$folder\" title=\"$folder\" onclick=\"showFolder('$folder')\">$leaf</div>" >> "$OUTPUT"
done
echo '  </div>' >> "$OUTPUT"

# Write content panels
echo '  <div class="content">' >> "$OUTPUT"

total_count=0
for folder in "${folders[@]}"; do
  echo "  <div class=\"folder-panel\" id=\"folder-$folder\">" >> "$OUTPUT"
  echo "    <h2>$folder</h2>" >> "$OUTPUT"
  echo "    <table>" >> "$OUTPUT"
  echo "      <thead><tr><th>#</th><th>File Path</th></tr></thead>" >> "$OUTPUT"
  echo "      <tbody>" >> "$OUTPUT"

  file_num=0
  while IFS= read -r filepath; do
    relpath="${filepath#$PDF_DIR/}"
    filename="$(basename "$relpath")"
    file_num=$((file_num + 1))
    total_count=$((total_count + 1))
    echo "        <tr>" >> "$OUTPUT"
    echo "          <td>$file_num</td>" >> "$OUTPUT"
    echo "          <td><a class=\"file-path\" href=\"$relpath\" target=\"_blank\" rel=\"noopener\">$relpath</a><button class=\"download-btn\" onclick=\"downloadFile('$relpath','$filename')\">Download</button></td>" >> "$OUTPUT"
    echo "        </tr>" >> "$OUTPUT"
  done < <(find "$PDF_DIR/$folder" -maxdepth 1 -name "*.pdf" | sort)

  echo "      </tbody>" >> "$OUTPUT"
  echo "    </table>" >> "$OUTPUT"
  echo "  </div>" >> "$OUTPUT"
done

cat >> "$OUTPUT" <<'HTMLFOOT'
  </div>
</div>
<script>
  var first = document.querySelector('.nav-item');
  if (first) showFolder(first.getAttribute('data-folder'));
</script>
</body>
</html>
HTMLFOOT

echo "Generated $OUTPUT with $total_count entries."
