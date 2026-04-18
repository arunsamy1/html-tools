# PROMPT.md — Recreating the Index Generator Scripts

This file documents the requirements and design decisions behind `generate.sh` and `generate_pdf.sh` so the scripts can be recreated or modified from scratch.

---

## Purpose

These are bash scripts that auto-generate a static HTML index page by scanning subdirectories for files. No tree structure — only one level of subdirectories (flat folders).

- `generate.sh` → scans for `*.html` files → outputs `index.html`
- `generate_pdf.sh` → scans for `*.pdf` files → outputs `index_pdf.html`

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

## Script Logic (generate.sh)

```
1. Find all *.html files under subdirectories (mindepth 2, not root-level files)
2. Extract unique folder names in sorted order (preserving first-seen order)
3. Write HTML head: styles + JS functions (showFolder, openFile, goBack, downloadFile)
4. Write sidebar: one nav-item div per folder, first folder gets class "active"
5. For each folder:
     - Write a folder-panel div (hidden by default via CSS)
     - Find *.html files in that folder (maxdepth 1)
     - Write a table row per file with filename link + Open in new tab + Download buttons
6. Write iframe viewer bar and iframe element (hidden by default)
7. Write inline script to show the first folder on page load
```

## Script Logic (generate_pdf.sh)

Identical to `generate.sh` with these differences:
- Scans for `*.pdf` instead of `*.html`
- Output file is `index_pdf.html` instead of `index.html`
- Page title is "PDF File Index"
- Prints a warning and skips writing if no PDFs are found

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
cd /docuserver/www/opt_html
./generate.sh       # regenerates index.html
./generate_pdf.sh   # regenerates index_pdf.html
```

Run either script whenever files are added or removed from subdirectories.
