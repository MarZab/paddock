extension MarkdownPage {
    /// The page's look: GitHub-like, light and dark from the system appearance.
    static let stylesheet = """
    :root { color-scheme: light dark; --fg: #1f2328; --muted: #59636e; --line: #d1d9e0; --soft: #f6f8fa;
      --link: #0969da; --code: rgba(129,139,152,.15); }
    @media (prefers-color-scheme: dark) {
      :root { --fg: #e6edf3; --muted: #9198a1; --line: #3d444d; --soft: #151b23; --link: #4493f8;
        --code: rgba(101,108,118,.3); } }
    html { background: Canvas; }
    body { margin: 0; color: var(--fg); background: Canvas;
      font: 14px/1.55 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
    main { padding: 36px 28px 48px; max-width: 1100px; overflow-wrap: break-word; }
    h1, h2, h3, h4, h5, h6 { margin: 1.4em 0 .6em; line-height: 1.25; font-weight: 600; }
    h1 { font-size: 1.9em; padding-bottom: .3em; border-bottom: 1px solid var(--line); }
    h2 { font-size: 1.45em; padding-bottom: .3em; border-bottom: 1px solid var(--line); }
    h3 { font-size: 1.2em; } h4 { font-size: 1em; } h5, h6 { font-size: .9em; color: var(--muted); }
    main > :first-child { margin-top: 0; }
    p, ul, ol, blockquote, pre, .table, table.front-matter, pre.front-matter { margin: 0 0 1em; }
    ul, ol { padding-left: 2em; } li + li { margin-top: .25em; } li > p { margin: .25em 0; }
    li > ul, li > ol { margin: .25em 0 0; }
    li.task { list-style: none; } li.task input { margin: 0 .4em 0 -1.4em; vertical-align: middle; }
    a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
    .dead-link { text-decoration: underline dotted; }
    .dead-image { color: var(--muted); }
    code, pre { font: 12.5px/1.45 ui-monospace, "SF Mono", Menlo, monospace; }
    code { background: var(--code); padding: .15em .35em; border-radius: 5px; white-space: break-spaces; }
    pre { background: var(--soft); padding: 12px 14px; border-radius: 6px; overflow: auto; }
    pre code { background: none; padding: 0; white-space: pre; }
    blockquote { padding: 0 1em; color: var(--muted); border-left: .25em solid var(--line); }
    hr { height: 2px; border: 0; background: var(--line); margin: 1.5em 0; }
    img { max-width: 100%; }
    .table { overflow-x: auto; }
    table { border-collapse: collapse; }
    .table table { width: max-content; max-width: 100%; }
    th, td { border: 1px solid var(--line); padding: 5px 10px; vertical-align: top; text-align: left; }
    th { font-weight: 600; background: var(--soft); }
    tbody tr:nth-child(2n) { background: var(--soft); }
    table.front-matter, pre.front-matter { font-size: 12px; color: var(--muted); }
    table.front-matter th, table.front-matter td { border: 0; padding: 1px 12px 1px 0; background: none; }
    table.front-matter th { font-weight: 500; }
    pre.raw-html { white-space: pre-wrap; }
    """
}
