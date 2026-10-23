# PROMPT.md — Recreating the Index Generator Scripts

This file documents the requirements and design decisions behind `generate_html.sh`, `generate_pdf.sh`, `generate_jar.sh` and `generate_mp3.sh` so the scripts can be recreated or modified from scratch.

---

## Purpose

These are bash scripts that auto-generate a static HTML index page by scanning subdirectories for files. No tree structure — only one level of subdirectories (flat folders).

- `generate_html.sh` → scans for `*.html` files → outputs `index.html`
- `generate_pdf.sh` → scans for `*.pdf` files → outputs `index_pdf.html`
- `generate_jar.sh` → scans for `*.jar` files → outputs `index_jar.html`
- `generate_mp3.sh` → scans for `*.mp3` files → outputs `index_mp3.html`, with an inline player per track

---

## Configuration

The folder to scan is **not** derived from the script's location. Each script reads
its own properties file, by default sitting next to it:

| Script              | Properties file            | Dir key    | Env var to override the path |
|---------------------|----------------------------|------------|------------------------------|
| `generate_html.sh`  | `generate_html.properties` | `html.dir` | `GENERATE_HTML_PROPERTIES`   |
| `generate_pdf.sh`   | `generate_pdf.properties`  | `pdf.dir`  | `GENERATE_PDF_PROPERTIES`    |
| `generate_jar.sh`   | `generate_jar.properties`  | `jar.dir`  | `GENERATE_JAR_PROPERTIES`    |
| `generate_mp3.sh`   | `generate_mp3.properties`  | `mp3.dir`  | `GENERATE_MP3_PROPERTIES`    |

```properties
# generate_html.properties
html.dir=/opt_html
output.file=index.html
```

```properties
# generate_pdf.properties
pdf.dir=/opt_html
output.file=index_pdf.html
```

```properties
# generate_jar.properties
jar.dir=/opt_jars
output.file=index_jar.html
```

```properties
# generate_mp3.properties
mp3.dir=/opt_mp3
output.file=index_mp3.html
```

- `html.dir` / `pdf.dir` / `jar.dir` / `mp3.dir` — folder to scan; the generated index page is
  written into it. Absolute, or relative to the properties file's own directory
- `output.file` — name of the generated page inside that folder. Defaults to
  `index.html`, `index_pdf.html`, `index_jar.html` and `index_mp3.html` respectively
- Format is `key=value`; `#` comment lines, surrounding whitespace and optional
  quotes around the value are all handled; the last value for a key wins
- A script exits 1 with a message if its properties file is missing, its directory
  key is unset, or that directory does not exist

**Do not point two scripts' `output.file` at the same name in the same folder** —
whichever runs last wins.

---

## Page Layout

The generated HTML page has a two-pane layout:

### Left Pane (Sidebar)
- Fixed width: **280px**
- Background color: **light blue (`#add8e6`)**
- Title at the top: **"Home"**
- Lists all **folder names** (subdirectory names) as clickable nav items
- Clicking a folder name shows that folder's files in the right pane
- Active folder is highlighted in a darker blue (`#4a8fa8`) with white bold text
- Folders without any matching files are excluded from the nav

### Right Pane (Content)
- Takes up the remaining width (`flex: 1`)
- Shows only the **currently selected folder's files** as a table
- Table columns: `#` (row number) and `File`
- Each file row has three actions:
  1. **Filename link** — clicking loads the file in an inline iframe within the right pane
  2. **"Open in new tab" button** (blue) — opens the file in a new browser tab
  3. **"Download" button** (green) — forces a file download using fetch → blob → object URL (required to avoid the browser rendering HTML/PDF instead of downloading)

### File Viewer (Iframe)
- When a filename link is clicked, an `<iframe>` fills the right pane showing the file
- A **"← Back" button** (grey) appears above the iframe with the filename
- Clicking "← Back" returns to the folder's file table
- Clicking any folder in the left nav also dismisses the iframe and shows the table

---

## Behavior Details

- **First folder** is selected and visible by default on page load
- **Only one folder panel** is visible at a time (JS toggles `display:none/block`)
- **Download** uses `fetch(url).then(res => res.blob())` then creates a temporary `<a download>` pointing to an object URL — this forces a save dialog even for HTML/PDF files that browsers would otherwise render
- **Files must be served over HTTP** (not `file://`) for `fetch()` and iframe to work correctly

---

## Mobile Responsiveness

- At screen width ≤ 600px:
  - The layout switches from side-by-side to vertical (`flex-direction: column`)
  - The sidebar becomes a full-width top bar
  - Content padding reduces to 20px

---

## Script Logic (generate_html.sh)

```
1. Read `html.dir` and `output.file` from the properties file
2. Find all *.html files under subdirectories (mindepth 2, not root-level files)
3. Extract unique folder names in sorted order (preserving first-seen order)
4. Write HTML head: styles + JS functions (showFolder, openFile, goBack, downloadFile)
5. Write sidebar: one nav-item div per folder, first folder gets class "active"
6. For each folder:
     - Write a folder-panel div (hidden by default via CSS)
     - Find *.html files in that folder (maxdepth 1)
     - Write a table row per file with filename link + Open in new tab + Download buttons
7. Write iframe viewer bar and iframe element (hidden by default)
8. Write inline script to show the first folder on page load
```

## Script Logic (generate_pdf.sh / generate_jar.sh)

Both are identical to `generate_html.sh` with these differences:
- Read their own properties file and dir key (see the Configuration table)
- Scan for `*.pdf` / `*.jar` instead of `*.html`
- `output.file` defaults to `index_pdf.html` / `index_jar.html`
- Page title is "PDF File Index" / "JAR File Index"
- Print a warning to stderr, exit 0 and leave any existing output file untouched
  when no matching files are found

Additionally:

`generate_jar.sh` additionally has **no Download button**: each row is just the
file-path link. The `.download-btn` CSS and the `downloadFile()` JS are omitted from
that page as well, since nothing references them. A browser cannot render a JAR, so
the plain link already downloads or prompts.

Everything else — the sidebar nav, the folder grouping and the table markup — is the
same across all three, so `index.html` and `index_pdf.html` are byte-identical apart
from the `<title>` and the file rows, and `index_jar.html` differs only by the title
and the dropped download markup.

---

## Script Logic (generate_mp3.sh)

Same as `generate_html.sh`, scanning for `*.mp3` and defaulting `output.file` to
`index_mp3.html`, with a warning-and-exit-0 when no MP3s are found (as for PDF/JAR).
Two additions:

### Inline player

The table has a third column, **Play**, holding one `<audio controls preload="none">`
per row. `preload="none"` matters: without it a folder of 200 tracks would start
fetching every file on page load. The filename link and the Download button are kept,
so a track can be played in place, opened in a tab, or saved.

Files must be served over HTTP for playback (`file://` will not stream reliably).
Only `.mp3` is indexed, so the browser's MP3 support is all that is required.

### Escaping

Music filenames routinely contain `#`, `&`, `'` and spaces, which silently break
playback or the download button. This script therefore escapes each path three ways:

| Helper         | Used for                  | Example                          |
|----------------|---------------------------|----------------------------------|
| `url_encode`   | `href` and `<audio src>`  | `track#1.mp3` → `track%231.mp3`  |
| `html_escape`  | the visible link text     | `Rock & Roll` → `Rock &amp; Roll`|
| `js_escape`    | the `downloadFile()` args | `Don't` → `Don\'t`               |

`url_encode` runs under `LC_ALL=C` so it iterates bytes and percent-encodes UTF-8
names correctly (`Café.mp3` → `Caf%C3%A9.mp3`). Without the encoding a `#` in a
filename is read as a URL fragment and the request 404s.

> The other three scripts do **not** yet apply this escaping — it matters far less
> for their file types, but a `.html`/`.pdf`/`.jar` named with `#`, `&` or `'` would
> hit the same bug there.

---

## Key CSS Classes

| Class/ID          | Purpose                                      |
|-------------------|----------------------------------------------|
| `.layout`         | Flex container for sidebar + content         |
| `.sidebar`        | Left nav pane                                |
| `.sidebar-title`  | "Home" heading in left pane                  |
| `.nav-item`       | Clickable folder name in sidebar             |
| `.nav-item.active`| Currently selected folder (darker blue)      |
| `.content`        | Right pane wrapper                           |
| `.folder-panel`   | Per-folder file table (hidden by default)    |
| `.open-btn`       | "Open in new tab" button (blue)              |
| `.download-btn`   | "Download" button (green)                    |
| `.back-btn`       | "← Back" button shown above iframe (grey)    |
| `#viewer-bar`     | Container for back button + filename label   |
| `#file-viewer`    | The iframe that displays the selected file   |

---

## How to Run

```bash
# Set html.dir / pdf.dir in the matching .properties file first, then run from anywhere:
/opt_html/admin/bin/generate_html.sh   # regenerates index.html
/opt_html/admin/bin/generate_pdf.sh    # regenerates index_pdf.html
/opt_html/admin/bin/generate_jar.sh    # regenerates index_jar.html
/opt_html/admin/bin/generate_mp3.sh    # regenerates index_mp3.html

# Or point any script at a different properties file:
GENERATE_HTML_PROPERTIES=/path/to/other.properties /opt_html/admin/bin/generate_html.sh
GENERATE_PDF_PROPERTIES=/path/to/other.properties  /opt_html/admin/bin/generate_pdf.sh
GENERATE_JAR_PROPERTIES=/path/to/other.properties  /opt_html/admin/bin/generate_jar.sh
GENERATE_MP3_PROPERTIES=/path/to/other.properties  /opt_html/admin/bin/generate_mp3.sh
```

Run a script whenever files are added or removed from subdirectories.
