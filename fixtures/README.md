# Fixtures

Markdown documents for checking the app by hand. None of them are used by the unit tests.

| File | Use it to check |
|---|---|
| `rendering-check.md` | Frontmatter, inline styles, read-only task checkboxes, a table, a highlighted code block, KaTeX (inline and block), a Mermaid diagram, a GitHub alert, and find ("needle" occurs 3 times in the rendered text). Also the export spot-check (PDF/HTML). |
| `reader-layout.md` | Content width, page margins, alignment, vertical rhythm, and table wrapping. |
| `code-highlighting.md` | Code-block highlighting (highlight.js) in Swift, Python, bash, YAML, JSON, SQL, diff, Dockerfile, nginx, RouterOS, and a plain block; try it in Light, Dark, and a Base16 theme. |
| `long-document.md` | Scroll position: scroll to the middle, then rewrite the file from another program (append a line with an atomic write); the tab must reload without a prompt and stay where it was. |
| `folder-search/` | Open it as the folder (⌘⌥O), then Search in Folder (⌃⇧F) for `haystack`: two hits; Enter opens `sub/beta.md` on the match. |

Open a fixture in a Debug build with:

```bash
open -a "$PWD/build/Xcode/Debug/Hashlight.app" "$PWD/fixtures/rendering-check.md"
```

Launching a build registers it with Launch Services; run `./scripts/manage-dev-registrations.sh
unregister` when you finish.
