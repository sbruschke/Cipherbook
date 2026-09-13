import Foundation

/// Builds the CSS + JavaScript injected into the chapter web view.
enum ReaderRenderer {

    /// Body padding above the first line; the grid's first row is anchored to it.
    static let topPad: Double = 28

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
        let p = settings.palette
        let align = settings.justified ? "justify" : "left"
        // Ruby annotations need extra room between lines.
        let lh = settings.dualFont ? settings.lineHeight + 0.9 : settings.lineHeight
        let fallback = "-apple-system, \"Helvetica Neue\", serif"
        // Books routinely pin font-size on <p>; inheriting from <body> alone
        // would let their stylesheet win, so normalise the text containers.
        let textBlocks = "body p, body li, body dd, body dt, body div, body span, "
            + "body td, body th, body blockquote, body figcaption, body section, body article"

        return fontFaceCSS(for: faces) + """
        :root { color-scheme: \(p.isDark ? "dark" : "light"); }
        html { -webkit-text-size-adjust: 100% !important; background: \(p.background) !important; }
        body {
          background: \(p.background) !important;
          color: \(p.foreground) !important;
          margin: 0 !important;
          padding: \(Int(topPad))px \(Int(settings.margin))px 96px \(Int(settings.margin))px !important;
          font-size: \(Int(settings.fontSize))px !important;
          text-align: \(align) !important;
          -webkit-hyphens: auto; hyphens: auto;
          word-wrap: break-word; overflow-wrap: break-word;
        }
        body, body * {
          font-family: \(top.cssFamily), \(fallback) !important;
          color: \(p.foreground) !important;
          background-color: transparent !important;
          background-image: none !important;
          line-height: \(String(format: "%.2f", lh)) !important;
          letter-spacing: \(String(format: "%.2f", settings.letterSpacing))px !important;
          max-width: 100% !important;
        }
        \(settings.forceSize ? "\(textBlocks) { font-size: 1em !important; }" : "")
        body p, body li, body dd, body blockquote {
          text-align: \(align) !important;
        }
        img, svg, video { max-width: 100% !important; height: auto !important; }
        a, a * { color: \(p.accent) !important; text-decoration: none !important; }
        hr { border-color: \(p.muted) !important; }
        ::selection { background: \(p.accent)44; }
        \(punctCSS(settings))
        \(gridCSS(settings))
        ruby.cb-ruby {
          display: ruby;
          ruby-position: under;
          -webkit-ruby-position: after;
          ruby-align: center;
        }
        body ruby.cb-ruby rt.cb-rt {
          font-family: \(bottom.cssFamily), \(fallback) !important;
          font-size: \(String(format: "%.2f", settings.subScale))em !important;
          color: \(p.muted) !important;
          letter-spacing: 0 !important;
          line-height: 1.15 !important;
          font-weight: 400 !important;
          font-style: normal !important;
          text-transform: none !important;
          -webkit-user-select: none;
        }
        """
    }

    /// Punctuation is tinted by a class the `punctuationJS` pass installs, so the
    /// rule has to out-specify the blanket `body, body *` colour above — and the
    /// ruby rule below it, for punctuation that ends up inside an annotation.
    @MainActor
    static func punctCSS(_ settings: ReaderSettings) -> String {
        guard settings.colorPunctuation else { return "" }
        let c = settings.punctuationColor
        return """
        body .cb-punct, body ruby.cb-ruby rt.cb-rt .cb-punct { color: \(c) !important; }
        """
    }

    /// Dots at every character-cell corner, as in the print build's `--grid`:
    /// the pitch is the space advance across and the line box down, anchored to
    /// the text origin so the body type lands on the grid. The cell size is
    /// measured in the page by `cbMeasureGrid` and arrives as a CSS variable.
    @MainActor
    static func gridCSS(_ settings: ReaderSettings) -> String {
        guard settings.showGrid else { return "" }
        let c = settings.gridColor
        let r = String(format: "%.2f", max(0.4, settings.gridDot))
        let x = "var(--cb-cell-x, \(String(format: "%.2f", settings.fontSize * 0.5))px)"
        let y = "var(--cb-cell-y, \(String(format: "%.2f", settings.fontSize * settings.lineHeight))px)"
        // Painted on the root so it covers the whole canvas; `body` is kept
        // transparent by the reset above, so nothing hides it.
        return """
        :root {
          background-image: radial-gradient(circle, \(c) 0px, \(c) \(r)px, \(c)00 \(r)px) !important;
          background-size: \(x) \(y) !important;
          background-position: calc(\(Int(settings.margin))px - \(x) / 2) calc(\(Int(ReaderRenderer.topPad))px - \(y) / 2) !important;
          background-repeat: repeat !important;
          background-attachment: scroll !important;
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
      if (document.body) window.cbMeasureGrid();
      if (document.fonts && document.fonts.ready) {
        document.fonts.ready.then(function () { window.cbMeasureGrid(); });
      }
    };
    // The grid pitch is the advance of a space in the running font and the
    // height of a line box - both only knowable once the page has the font.
    window.cbMeasureGrid = function () {
      if (!document.body) return;
      var probe = document.createElement('span');
      probe.setAttribute('aria-hidden', 'true');
      probe.style.cssText = 'position:absolute;visibility:hidden;white-space:pre;' +
                            'left:-9999px;top:0;padding:0;margin:0;border:0;';
      probe.textContent = new Array(101).join(' ');
      document.body.appendChild(probe);
      var w = probe.getBoundingClientRect().width / 100;
      probe.parentNode.removeChild(probe);
      var cs = window.getComputedStyle(document.body);
      var fs = parseFloat(cs.fontSize) || 19;
      var lh = parseFloat(cs.lineHeight);
      if (!(w > 0.5)) w = fs * 0.5;
      if (!(lh > 0.5)) lh = fs * 1.6;
      var root = document.documentElement;
      root.style.setProperty('--cb-cell-x', w.toFixed(3) + 'px');
      root.style.setProperty('--cb-cell-y', lh.toFixed(3) + 'px');
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

    /// Wraps every run of punctuation/symbol characters in `<span class="cb-punct">`
    /// so it can be tinted independently, matching the print edition's treatment.
    /// Runs after `dualFontJS` and deliberately descends into ruby annotations.
    static let punctuationJS = """
    (function () {
      if (!document.body || document.body.dataset.cbPunct === '1') return;
      document.body.dataset.cbPunct = '1';
      var SKIP = { SCRIPT:1, STYLE:1, NOSCRIPT:1, PRE:1, CODE:1, TEXTAREA:1,
                   SVG:1, MATH:1, HEAD:1, TITLE:1, KBD:1, SAMP:1 };
      // Unicode categories P (punctuation) and S (symbols), as in the print build.
      var SPLIT = /([\\p{P}\\p{S}]+)/u;
      var HAS = /[\\p{P}\\p{S}]/u;
      var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: function (n) {
          if (!n.nodeValue || !HAS.test(n.nodeValue)) return NodeFilter.FILTER_REJECT;
          var p = n.parentNode;
          while (p && p.nodeType === 1) {
            if (SKIP[p.nodeName.toUpperCase()]) return NodeFilter.FILTER_REJECT;
            if (p.classList && p.classList.contains('cb-punct')) return NodeFilter.FILTER_REJECT;
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
        n.nodeValue.split(SPLIT).forEach(function (tok) {
          if (!tok) return;
          if (!HAS.test(tok)) { frag.appendChild(document.createTextNode(tok)); return; }
          var span = document.createElement('span');
          span.className = 'cb-punct';
          span.textContent = tok;
          frag.appendChild(span);
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
