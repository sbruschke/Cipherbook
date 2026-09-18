// Rebuilds ReaderRenderer's stylesheet from the Swift source, so these tests run against
// the CSS the app really ships. Every `\(…)` must have a value here; an unknown one throws
// rather than quietly testing different CSS from the app's.
import { readFileSync } from 'fs';

const SETTINGS = {
  'p.isDark ? "dark" : "light"': 'dark',
  'p.background': '#1c1c1e', 'p.foreground': '#d9d9de', 'p.muted': '#9a9aa2', 'p.accent': '#7aa9e0',
  'Int(topPad)': '28', 'Int(ReaderRenderer.topPad)': '28',
  'Int(settings.margin)': '22', '2 * m': '44', 'm': '22', 'top': '28', 'bottom': '44',
  'Int(settings.fontSize)': '19', 'align': 'left',
  'String(format: "%.2f", lh)': '1.60',
  'String(format: "%.2f", settings.letterSpacing)': '0.00',
  'settings.forceSize ? "\\(textBlocks) { font-size: 1em !important; }" : ""':
    'body p, body li, body dd, body dt, body div, body span, body td, body th, body blockquote, body figcaption, body section, body article { font-size: 1em !important; }',
  'punctCSS(settings)': '', 'gridCSS(settings)': '',
  'bottom.cssFamily': 'Courier', 'top.cssFamily': 'Georgia', 'fallback': '-apple-system, serif',
  'String(format: "%.2f", settings.subScale)': '0.60',
  'punctFontCSS(bottom, fallback)':
    'body ruby.cb-ruby rt.cb-rt .cb-punct { font-family: Courier, -apple-system, serif !important; font-size: inherit !important; letter-spacing: 0 !important; }',
  'size': '47.5', 'punct': '', 'sub': '#9a9aa2', 'top + bottom': '72',
  'pagedCSS(settings)': null,      // filled in below from the source itself
  'wordCSS(settings, top: top, bottom: bottom, fallback: fallback)': null,
};

function fill(template, source) {
  return template.replace(/\\\(((?:[^()]|\([^()]*\))*)\)/g, (_, expr) => {
    if (!(expr in SETTINGS)) throw new Error(`css.mjs has no value for \\(${expr})`);
    const v = SETTINGS[expr];
    return v === null ? block(source, expr.split('(')[0]) : v;
  });
}

/// The `return """ … """` of one function in ReaderRenderer.swift.
function block(source, fn) {
  const at = source.indexOf(`static func ${fn}(`);
  if (at < 0) throw new Error(`no function ${fn}`);
  const marker = 'return """';
  const start = source.indexOf(marker, at) + marker.length;
  return fill(source.slice(start, source.indexOf('"""', start)), source);
}

export function readerCSS(path) {
  const source = readFileSync(path, 'utf8');
  // css() returns `fontFaceCSS(...) + """ … """`; the font faces are irrelevant here.
  const at = source.indexOf('return fontFaceCSS(for: faces) + """');
  const start = source.indexOf('"""', at) + 3;
  return fill(source.slice(start, source.indexOf('\n        """', start)), source);
}
