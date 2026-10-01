import Foundation

enum HelpHTML {
    static let content = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <style>
            :root { color-scheme: light dark; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
                line-height: 1.6;
                color: #1d1d1f;
                background-color: #ffffff;
                padding: 30px 40px;
                max-width: 700px;
            }
            h1 { font-size: 32px; font-weight: 700; margin-bottom: 30px; border-bottom: 1px solid #d2d2d7; padding-bottom: 15px; }
            h2 { font-size: 24px; font-weight: 600; margin-top: 30px; margin-bottom: 12px; }
            h3 { font-size: 18px; font-weight: 600; margin-top: 20px; margin-bottom: 10px; }
            p { margin-bottom: 12px; font-size: 14px; }
            ul { margin-left: 20px; margin-bottom: 12px; }
            li { margin-bottom: 6px; font-size: 14px; }
            code { background-color: #f5f5f7; padding: 2px 6px; border-radius: 3px; font-family: "SF Mono", Monaco, monospace; font-size: 13px; }
            kbd { display: inline-block; background-color: #f5f5f7; border: 1px solid #d2d2d7; border-radius: 3px; padding: 2px 6px; font-size: 12px; box-shadow: 0 1px 2px rgba(0,0,0,0.1); }
            table { width: 100%; border-collapse: collapse; margin: 20px 0; font-size: 14px; }
            th, td { padding: 10px; text-align: left; border-bottom: 1px solid #d2d2d7; }
            th { font-weight: 600; background-color: #f5f5f7; }
            strong { font-weight: 600; }

            @media (prefers-color-scheme: dark) {
                body { color: #f5f5f7; background-color: #1c1c1e; }
                h1, th, td { border-color: #48484a; }
                code, kbd, th { background-color: #2c2c2e; }
                kbd { border-color: #636366; }
            }
        </style>
    </head>
    <body>
        <h1>Hashlight Help</h1>

        <h2>Getting Started</h2>
        <p>Hashlight is a lightweight macOS Markdown viewer for clean reading and professional document export. It never changes your files.</p>

        <h2>Opening Files</h2>
        <ul>
            <li>Press <kbd>⌘O</kbd> or the Open button in the toolbar to open files</li>
            <li>Drag and drop <code>.md</code> files onto the app</li>
            <li>Double-click Markdown files in Finder</li>
            <li>Access recent files from <strong>File → Open Recent</strong></li>
            <li>Open a folder with <kbd>⌘⌥O</kbd> to browse its Markdown files in the sidebar's <strong>Files</strong> view</li>
        </ul>

        <h2>Working with Tabs</h2>
        <ul>
            <li><kbd>⌘O</kbd> - Open new files in tabs</li>
            <li><kbd>⌘W</kbd> - Close current tab</li>
            <li><kbd>⌃Tab</kbd> - Next tab</li>
            <li><kbd>⌃⇧Tab</kbd> - Previous tab</li>
            <li>Drag tabs to reorder them; right-click a tab to refresh it, close other tabs, or reveal it in Finder</li>
        </ul>

        <h2>Finding Your Way</h2>
        <ul>
            <li><kbd>⌘F</kbd> - Find in the rendered document with the search field in the toolbar; <kbd>Return</kbd> or <kbd>⌘G</kbd> goes to the next match, <kbd>⌘⇧G</kbd> to the previous one, and <kbd>ESC</kbd> clears the search</li>
            <li><kbd>⌘⇧O</kbd> - Quick Open: jump to a file or heading</li>
            <li><kbd>⌃⇧F</kbd> - Search in Folder: find text across the open folder and open the file at that match</li>
            <li><kbd>⌘K</kbd> - Command palette</li>
            <li>The sidebar switches between <strong>Files</strong> (<kbd>⌘⌥1</kbd>), the open folder's Markdown files, and <strong>Outline</strong> (<kbd>⌘⌥2</kbd>), the document's headings; click a heading to jump to it. Show or hide the sidebar with the toolbar's sidebar button or <kbd>⌃⌘S</kbd>, and drag its edge to resize it</li>
            <li><kbd>⌘⇧F</kbd> - Focus mode hides everything but the document; press <kbd>ESC</kbd> or the Exit Focus Mode button at the top to leave it</li>
        </ul>

        <h2>Files That Change</h2>
        <p>When another app saves an open file, its tab reloads automatically and keeps your reading position. If the file is deleted, Hashlight asks before closing the tab. <kbd>⌘R</kbd> reloads the current tab by hand.</p>

        <h2>Customizing Appearance</h2>
        <p>Press <kbd>⌘,</kbd> to open Settings. It has three panes: <strong>General</strong> (appearance and Dock icon), <strong>Preview</strong> (themes, fonts, and layout), and <strong>Tables</strong> (column categories). Settings reopens on the pane you used last.</p>
        <h3>Application Appearance (General)</h3>
        <ul>
            <li><strong>System</strong> - Follows macOS appearance</li>
            <li><strong>Light</strong> - Always light mode</li>
            <li><strong>Dark</strong> - Always dark mode</li>
        </ul>
        <h3>Dock Icon (General)</h3>
        <ul>
            <li><strong>System</strong> - Leaves the icon to macOS. On macOS 26 it follows the icon style in System Settings → Appearance; on earlier versions it shows Frost in Light mode and Ember in Dark mode.</li>
            <li><strong>Frost</strong> - Always the light icon</li>
            <li><strong>Ember</strong> - Always the dark icon</li>
        </ul>
        <p>The choice changes the icon in the Dock, the app switcher, the welcome screen, and Hashlight → About Hashlight while Hashlight runs. Finder keeps the standard icon.</p>
        <h3>Theme (Viewing)</h3>
        <p>Use the <strong>Light mode</strong> and <strong>Dark mode</strong> menus to choose a
        separate theme for each appearance. <strong>System</strong> uses macOS's own colors: the
        text background, label and separator colors, your accent color for headings and links, and
        the system reds, greens and so on for code; it follows changes to the accent color and to
        Increase Contrast. The other entries are Base16 palettes. The preview switches between the
        light and dark choice automatically when the effective application appearance changes.</p>
        <h3>Fonts (Viewing)</h3>
        <ul>
            <li><strong>Main font</strong> - Proportional font used for headings, paragraphs, lists, and tables</li>
            <li><strong>Fixed font</strong> - Monospaced font used for fenced code blocks and inline commands</li>
        </ul>
        <h3>Layout and Zoom</h3>
        <p>Set the text column's alignment, width and page margin in Settings → Viewing or from the status bar. Zoom with <kbd>⌘=</kbd>, <kbd>⌘-</kbd> and <kbd>⌘0</kbd> (View menu), the status bar, or pinch on a trackpad.</p>
        <h3>Table Columns (Tables)</h3>
        <p>Table columns get room in proportion to the weight of the first category whose words match the column header. Add, remove, edit, and reorder categories (drag a row, or <kbd>⌥↑</kbd> / <kbd>⌥↓</kbd>); <strong>Restore Defaults</strong> brings back the built-in set.</p>

        <h2>Exporting Documents</h2>
        <p>Export via <strong>File → Export</strong> or the Export button in the toolbar:</p>
        <ul>
            <li><strong>PDF</strong> - Formatted with pagination</li>
            <li><strong>HTML</strong> - With or without styles</li>
            <li><strong>Word (.docx)</strong> - Microsoft Word format</li>
            <li><strong>Word (.rtf)</strong> - Rich text for older word processors</li>
        </ul>
        <p>Press <kbd>⌘P</kbd> to print.</p>

        <h2>Keyboard Shortcuts</h2>
        <table>
            <tr><th>Shortcut</th><th>Action</th></tr>
            <tr><td><kbd>⌘O</kbd></td><td>Open files</td></tr>
            <tr><td><kbd>⌘⌥O</kbd></td><td>Open folder</td></tr>
            <tr><td><kbd>⌘⇧O</kbd></td><td>Quick Open</td></tr>
            <tr><td><kbd>⌃⇧F</kbd></td><td>Search in folder</td></tr>
            <tr><td><kbd>⌘K</kbd></td><td>Command palette</td></tr>
            <tr><td><kbd>⌘W</kbd></td><td>Close tab</td></tr>
            <tr><td><kbd>⌘R</kbd></td><td>Refresh</td></tr>
            <tr><td><kbd>⌘F</kbd></td><td>Find</td></tr>
            <tr><td><kbd>⌘G</kbd> / <kbd>⌘⇧G</kbd></td><td>Next / previous match</td></tr>
            <tr><td><kbd>⌘⇧F</kbd></td><td>Focus mode</td></tr>
            <tr><td><kbd>⌃⌘S</kbd></td><td>Show / hide the sidebar</td></tr>
            <tr><td><kbd>⌘⌥1</kbd> / <kbd>⌘⌥2</kbd></td><td>Sidebar: Files / Outline</td></tr>
            <tr><td><kbd>⌘P</kbd></td><td>Print</td></tr>
            <tr><td><kbd>⌘=</kbd> / <kbd>⌘-</kbd> / <kbd>⌘0</kbd></td><td>Zoom in / out / reset</td></tr>
            <tr><td><kbd>⌘,</kbd></td><td>Settings</td></tr>
            <tr><td><kbd>⌘?</kbd></td><td>Help</td></tr>
            <tr><td><kbd>⌘Q</kbd></td><td>Quit</td></tr>
            <tr><td><kbd>⌃Tab</kbd></td><td>Next tab</td></tr>
            <tr><td><kbd>⌃⇧Tab</kbd></td><td>Previous tab</td></tr>
            <tr><td><kbd>ESC</kbd></td><td>Close Settings/Help</td></tr>
        </table>

        <h2>Supported Markdown</h2>
        <ul>
            <li>Headings (H1-H6)</li>
            <li>Bold (<code>**text**</code>) and italic (<code>*text*</code>) — underscore emphasis (<code>_text_</code>) is not supported</li>
            <li>Strikethrough, highlight, inline code</li>
            <li>Bullet and numbered lists</li>
            <li>Task lists (shown as checkboxes; they are read-only)</li>
            <li>Code blocks with syntax highlighting</li>
            <li>Tables</li>
            <li>Images (local and remote)</li>
            <li>Mermaid diagrams and LaTeX math</li>
            <li>GitHub alerts such as <code>&gt; [!NOTE]</code></li>
            <li>Horizontal rules</li>
        </ul>

        <h2>Tips</h2>
        <ul>
            <li>Settings are automatically saved</li>
            <li>Use <kbd>⌘W</kbd> to close tabs - app stays open</li>
            <li>Hashlight remembers where you were in each document</li>
            <li>Export formats preserve formatting</li>
            <li>Recent files persist between launches</li>
        </ul>
    </body>
    </html>
    """
}
