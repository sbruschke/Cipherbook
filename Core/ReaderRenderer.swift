import Foundation

/// Builds the CSS + JavaScript injected into the chapter web view.
enum ReaderRenderer {

    @MainActor
    static func fontFaceCSS(for fonts: [FontChoice]) -> String {
        var seen = Set<String>()
        var out = ""
        for font in fonts {
            guard let url = font.fileURL else { continue }
            let family = FontLibrary.cssFamilyName(for: url)
            guard seen.insert(family).inserted else { continue }
            let format: String
            switch url.pathExtension.lowercased() {
            case "otf":   format = "opentype"
            case "woff":  format = "woff"
            case "woff2": format = "woff2"
            case "ttc":   format = "truetype"
            default:      format = "truetype"
            }
            out += """
            @font-face { font-family: "\(family)"; \
            src: url("\(url.absoluteString)") format("\(format)"); \
            font-display: block; }

            """
        }
        return out
    }

    /// `top` is the font of the running text, `bottom` the ruby annotation under it.
    @MainActor
    static func css(settings: ReaderSettings,
                    top: FontChoice,
                    bottom: FontChoice,
                    faces: [FontChoice]) -> String {
        let t = settings.theme
        let align = settings.justified ? "justify" : "left"
        // Ruby annotations need extra room between lines.
        let lh = settings.dualFont ? settings.lineHeight + 0.9 : settings.lineHeight
        let accent = t.isDark ? "#7aa9e0" : "#2b6cb0"
        let fallback = "-apple-system, \"Helvetica Neue\", serif"

        return fontFaceCSS(for: faces) + """
        :root { color-scheme: \(t.isDark ? "dark" : "light"); }
        html { -webkit-text-size-adjust: 100% !important; background: \(t.background) !important; }
        body {
          background: \(t.background) !important;
          color: \(t.foreground) !important;
          margin: 0 !important;
          padding: 28px \(Int(settings.margin))px 96px \(Int(settings.margin))px !important;
          font-size: \(Int(settings.fontSize))px !important;
          line-height: \(String(format: "%.2f", lh)) !important;
          text-align: \(align) !important;
          letter-spacing: \(String(format: "%.2f", settings.letterSpacing))px !important;
          -webkit-hyphens: auto; hyphens: auto;
          word-wrap: break-word; overflow-wrap: break-word;
        }
        body, body * {
          font-family: \(top.cssFamily), \(fallback) !important;
          color: \(t.foreground) !important;
          background-color: transparent !important;
          max-width: 100% !important;
        }
        img, svg, video { max-width: 100% !important; height: auto !important; }
        a, a * { color: \(accent) !important; text-decoration: none !important; }
        hr { border-color: \(t.muted) !important; }
        ::selection { background: \(accent)44; }
        ruby.cb-ruby {
          display: ruby;
          ruby-position: under;
          -webkit-ruby-position: after;
          ruby-align: center;
        }
        body ruby.cb-ruby rt.cb-rt {
          font-family: \(bottom.cssFamily), \(fallback) !important;
          font-size: \(String(format: "%.2f", settings.subScale))em !important;
          color: \(t.muted) !important;
          letter-spacing: 0 !important;
          line-height: 1.15 !important;
          font-weight: 400 !important;
          font-style: normal !important;
          text-transform: none !important;
          -webkit-user-select: none;
        }
        """
    }

    /// Installed at document start; the style element survives later updates.
    static let bootstrapJS = """
    window.cbSetStyle = function (css) {
      var el = document.getElementById('cb-style');
      if (!el) {
        el = document.createElement('style');
        el.id = 'cb-style';
        (document.head || document.documentElement).appendChild(el);
      }
      el.textContent = css;
    };
    window.cbScrollFraction = function () {
      var h = document.documentElement.scrollHeight - window.innerHeight;
      return h > 0 ? window.pageYOffset / h : 0;
    };
    window.cbScrollTo = function (f) {
      var h = document.documentElement.scrollHeight - window.innerHeight;
      window.scrollTo(0, Math.max(0, f * h));
    };
    """

    /// Wraps every word in `<ruby>word<rt>word</rt></ruby>` so the same text can
    /// be shown in two typefaces at once.
    static let dualFontJS = """
    (function () {
      if (!document.body || document.body.dataset.cbDual === '1') return;
      document.body.dataset.cbDual = '1';
      var SKIP = { SCRIPT:1, STYLE:1, NOSCRIPT:1, RUBY:1, RT:1, RP:1, PRE:1, CODE:1,
                   TEXTAREA:1, SVG:1, MATH:1, HEAD:1, TITLE:1, KBD:1, SAMP:1 };
      var WORD = /[0-9A-Za-z\\u00C0-\\u024F\\u0370-\\u1FFF\\u2C00-\\uD7FF]/;
      var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: function (n) {
          if (!n.nodeValue || !/\\S/.test(n.nodeValue)) return NodeFilter.FILTER_REJECT;
          var p = n.parentNode;
          while (p && p.nodeType === 1) {
            if (SKIP[p.nodeName.toUpperCase()]) return NodeFilter.FILTER_REJECT;
            p = p.parentNode;
          }
          return NodeFilter.FILTER_ACCEPT;
        }
      });
      var nodes = [];
      while (walker.nextNode()) nodes.push(walker.currentNode);
      nodes.forEach(function (n) {
        if (!n.parentNode) return;
        var frag = document.createDocumentFragment();
        n.nodeValue.split(/(\\s+)/).forEach(function (tok) {
          if (!tok) return;
          if (!WORD.test(tok)) { frag.appendChild(document.createTextNode(tok)); return; }
          var ruby = document.createElement('ruby');
          ruby.className = 'cb-ruby';
          ruby.appendChild(document.createTextNode(tok));
          var rt = document.createElement('rt');
          rt.className = 'cb-rt';
          rt.textContent = tok;
          ruby.appendChild(rt);
          frag.appendChild(ruby);
        });
        n.parentNode.replaceChild(frag, n);
      });
    })();
    """

    /// Reports taps (for chrome toggling) and scroll position back to Swift.
    static let bridgeJS = """
    (function () {
      document.addEventListener('click', function (e) {
        var el = e.target;
        while (el && el.nodeType === 1) {
          if (el.tagName === 'A') return;
          el = el.parentNode;
        }
        window.webkit.messageHandlers.cb.postMessage({ type: 'tap' });
      }, true);
      var pending = false;
      window.addEventListener('scroll', function () {
        if (pending) return;
        pending = true;
        setTimeout(function () {
          pending = false;
          window.webkit.messageHandlers.cb.postMessage({
            type: 'scroll', value: window.cbScrollFraction()
          });
        }, 250);
      }, { passive: true });
    })();
    """
}
