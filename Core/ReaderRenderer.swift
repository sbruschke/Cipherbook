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
        \(punctFontCSS(bottom, fallback))
        \(pagedCSS(settings))
        \(wordCSS(settings, top: top, bottom: bottom, fallback: fallback))
        """
    }

    /// Screen-sized pages as CSS columns, one column per screen. Always present but
    /// scoped to `html.cb-paged`, so switching modes is a class change, not a restyle.
    @MainActor
    static func pagedCSS(_ settings: ReaderSettings) -> String {
        let m = Int(settings.margin)
        let top = Int(topPad)
        let bottom = 44
        return """
        html.cb-paged, html.cb-paged body { overflow: hidden !important; }
        html.cb-paged body {
          box-sizing: border-box !important;
          height: 100vh !important;
          padding: \(top)px \(m)px \(bottom)px \(m)px !important;
          -webkit-column-width: calc(100vw - \(2 * m)px) !important;
          column-width: calc(100vw - \(2 * m)px) !important;
          -webkit-column-gap: \(2 * m)px !important;
          column-gap: \(2 * m)px !important;
          column-fill: auto !important;
          will-change: transform;
        }
        html.cb-paged img, html.cb-paged svg, html.cb-paged video {
          max-height: calc(100vh - \(top + bottom)px) !important;
          object-fit: contain;
        }
        """
    }

    /// The single-word overlay. It lives outside `<body>`, so the blanket body rules
    /// above don't reach it and it carries its own typography.
    @MainActor
    static func wordCSS(_ settings: ReaderSettings, top: FontChoice, bottom: FontChoice,
                        fallback: String) -> String {
        let p = settings.palette
        let size = String(format: "%.1f", settings.fontSize * settings.wordScale)
        let sub = settings.colorSubPunctuation ? settings.subPunctuationColor : p.muted
        let punct = settings.colorPunctuation ? """
        #cb-word .cb-punct { color: \(settings.punctuationColor); }
        #cb-word rt .cb-punct { color: \(sub); font-family: \(bottom.cssFamily), \(fallback); }
        """ : ""
        return """
        #cb-word { display: none; }
        html.cb-word, html.cb-word body { overflow: hidden !important; }
        html.cb-word body { visibility: hidden !important; }
        html.cb-word #cb-word {
          display: flex; flex-direction: column; align-items: center; justify-content: center;
          position: fixed; left: 0; top: 0; right: 0; bottom: 0; z-index: 2147483647;
          box-sizing: border-box; padding: 0 \(Int(settings.margin))px;
          background: \(p.background); color: \(p.foreground);
          -webkit-user-select: none; user-select: none;
        }
        #cb-word .cb-word-text {
          font-family: \(top.cssFamily), \(fallback);
          font-size: \(size)px; line-height: 1.3; text-align: center;
          letter-spacing: \(String(format: "%.2f", settings.letterSpacing))px;
          overflow-wrap: anywhere; max-width: 100%;
        }
        #cb-word ruby { display: ruby; ruby-position: under; -webkit-ruby-position: after; ruby-align: center; }
        #cb-word rt {
          font-family: \(bottom.cssFamily), \(fallback);
          font-size: \(String(format: "%.2f", settings.subScale))em;
          color: \(p.muted); line-height: 1.15; letter-spacing: 0;
        }
        #cb-word .cb-word-count {
          position: absolute; bottom: 28px; left: 0; right: 0; text-align: center;
          font: 13px -apple-system, sans-serif; color: \(p.muted);
          font-variant-numeric: tabular-nums;
        }
        \(punct)
        """
    }

    /// Punctuation is tinted by a class the `punctuationJS` pass installs, so the
    /// rule has to out-specify the blanket `body, body *` colour above.
    ///
    /// The two layers are tinted separately: `body .cb-punct` would otherwise reach
    /// into the annotation too, so the sub rule always follows it to take that back,
    /// either to its own colour or to the sub text colour.
    ///
    /// The font rule is not optional. `body, body *` sets the main family with
    /// `!important`, and it matches these spans directly wherever they sit —
    /// including inside `rt` — so a directly-matching declaration beats the sub
    /// family the `rt` rule can only pass down by inheritance. Without this,
    /// turning colouring on silently switches the annotation's punctuation to the
    /// main font.
    @MainActor
    static func punctCSS(_ settings: ReaderSettings) -> String {
        guard settings.colorPunctuation else { return "" }
        let c = settings.punctuationColor
        let sub = settings.colorSubPunctuation ? settings.subPunctuationColor : settings.palette.muted
        return """
        body .cb-punct { color: \(c) !important; }
        body ruby.cb-ruby rt.cb-rt .cb-punct { color: \(sub) !important; }
        """
    }

    /// Keeps punctuation spans inside an annotation on the sub font — see `punctCSS`
    /// for why the blanket `body *` rule would otherwise capture them.
    @MainActor
    static func punctFontCSS(_ bottom: FontChoice, _ fallback: String) -> String {
        """
        body ruby.cb-ruby rt.cb-rt .cb-punct {
          font-family: \(bottom.cssFamily), \(fallback) !important;
          font-size: inherit !important;
          letter-spacing: 0 !important;
        }
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
      var keep = window.cbCurrentWord ? window.cbCurrentWord() : null;
      el.textContent = css;
      if (keep !== null && window.cbAfterLayout) {
        window.cbAfterLayout(function () { window.cbGoToWord(keep); });
      }
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

    /// Reading position, page turning and the word-at-a-time view. Installed at document
    /// start (after `bootstrapJS`); functions only, nothing runs until Swift calls them.
    ///
    /// Positions are word indexes: every whitespace-separated run that contains a letter or
    /// digit, in document order, ignoring ruby annotations. That is the same whether the
    /// page is wrapped for two fonts or tinted, and whatever the layout, so one number
    /// restores the place in scroll, page and word modes alike.
    static let navigationJS = #"""
    (function () {
      var state = { mode: 'scroll', word: 0, dual: false, punct: false };
      var words = null;
      var observer = null;
      var SKIP = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, RT: 1, RP: 1, HEAD: 1, TITLE: 1 };
      var BLOCK = /^(P|DIV|H[1-6]|LI|UL|OL|BLOCKQUOTE|PRE|TD|TH|TR|DT|DD|DL|SECTION|ARTICLE|ASIDE|HEADER|FOOTER|FIGURE|FIGCAPTION|TABLE|BODY|HR|BR)$/;
      var HAS_WORD = /[\p{L}\p{N}]/u;
      var PUNCT = /([\p{P}\p{S}]+)/u;
      var IS_PUNCT = /[\p{P}\p{S}]/u;

      function post(msg) { window.webkit.messageHandlers.cb.postMessage(msg); }
      function isSpace(c) { return c === 32 || c === 9 || c === 10 || c === 13 || c === 12 || c === 160; }

      function skipped(node) {
        for (var p = node.parentNode; p && p.nodeType === 1; p = p.parentNode) {
          if (SKIP[p.nodeName.toUpperCase()] || p.id === 'cb-word') return true;
        }
        return false;
      }
      function blockOf(node) {
        var p = node.parentNode;
        while (p && p !== document.body && !BLOCK.test(p.nodeName.toUpperCase())) p = p.parentNode;
        return p;
      }

      function build() {
        words = [];
        if (!document.body) return words;
        if (!observer) {
          observer = new MutationObserver(function () { words = null; });
          observer.observe(document.body, { childList: true, subtree: true, characterData: true });
        }
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        var cur = null, lastBlock = null;
        function finish() {
          if (cur && HAS_WORD.test(cur.text)) words.push(cur);
          cur = null;
        }
        while (walker.nextNode()) {
          var n = walker.currentNode, s = n.nodeValue;
          if (!s || skipped(n)) continue;
          var b = blockOf(n);
          if (b !== lastBlock) { finish(); lastBlock = b; }
          var i = 0;
          while (i < s.length) {
            if (isSpace(s.charCodeAt(i))) { finish(); i++; continue; }
            var j = i;
            while (j < s.length && !isSpace(s.charCodeAt(j))) j++;
            if (!cur) cur = { node: n, offset: i, text: '' };
            cur.text += s.slice(i, j);
            i = j;
          }
        }
        finish();
        return words;
      }
      function list() { return words || build(); }

      function rectOf(w) {
        var range = document.createRange();
        range.setStart(w.node, w.offset);
        range.setEnd(w.node, Math.min(w.offset + 1, w.node.nodeValue.length));
        var rects = range.getClientRects();
        return rects.length ? rects[0] : w.node.parentNode.getBoundingClientRect();
      }

      // Pages are a translated column layout, one column per screen.
      var page = 0;
      function pageOf(rect) {
        return Math.floor((rect.left + page * window.innerWidth + 1) / window.innerWidth);
      }
      // Counted from where the last word or image sits, not the layout width: a trailing
      // margin can spill into an empty extra column that shouldn't become a blank page.
      function pageCount() {
        var last = 0, w = list();
        if (w.length) last = pageOf(rectOf(w[w.length - 1]));
        var media = document.body.querySelectorAll('img, svg, video');
        if (media.length) {
          var r = media[media.length - 1].getBoundingClientRect();
          if (r.width > 0) last = Math.max(last, pageOf(r));
        }
        return last + 1;
      }
      function setPage(n) {
        page = Math.max(0, Math.min(n, pageCount() - 1));
        document.body.style.transform = page ? 'translateX(' + (-page * window.innerWidth) + 'px)' : '';
      }

      // In scroll mode the reading line sits this far down, below the top bar. Saving and
      // restoring must use the same line, or every reopen drifts by a line.
      var READ_LINE = 60;

      // The first word at least partly in view (below the reading line, when scrolling).
      function firstVisible() {
        var w = list();
        if (!w.length) return 0;
        var paged = state.mode === 'paged';
        var lo = 0, hi = w.length - 1;
        while (lo < hi) {
          var mid = (lo + hi) >> 1, r = rectOf(w[mid]);
          if (paged ? r.right > 1 : r.bottom > READ_LINE + 1) hi = mid; else lo = mid + 1;
        }
        return lo;
      }

      window.cbCurrentWord = function () {
        if (!document.body) return null;
        return state.mode === 'word' ? state.word : firstVisible();
      };

      // Moves to word `i`; -1 means the last word (for stepping back a chapter).
      window.cbGoToWord = function (i) {
        var w = list();
        if (i < 0 || i >= w.length) i = i < 0 ? w.length - 1 : w.length - 1;
        state.word = Math.max(0, i);
        if (state.mode === 'word') {
          render();
        } else if (w.length) {
          var r = rectOf(w[state.word]);
          if (state.mode === 'paged') {
            setPage(pageOf(r));
          } else {
            window.scrollTo(0, Math.max(0, r.top + window.pageYOffset - READ_LINE));
          }
        }
        report();
      };

      window.cbAfterLayout = function (fn) {
        var run = function () {
          requestAnimationFrame(function () { requestAnimationFrame(fn); });
        };
        if (document.fonts && document.fonts.ready) document.fonts.ready.then(run); else run();
      };

      window.cbRestore = function (i) {
        window.cbAfterLayout(function () { window.cbGoToWord(i); });
      };

      window.cbSetMode = function (cfg) {
        var keep = window.cbCurrentWord();
        var changed = cfg.mode !== state.mode;
        state.mode = cfg.mode;
        state.dual = !!cfg.dual;
        state.punct = !!cfg.punct;
        var root = document.documentElement;
        root.classList.toggle('cb-paged', state.mode === 'paged');
        root.classList.toggle('cb-word', state.mode === 'word');
        if (state.mode !== 'paged' && document.body) { page = 0; document.body.style.transform = ''; }
        if (state.mode === 'word') render();
        if (changed && keep !== null) {
          window.cbAfterLayout(function () { window.cbGoToWord(keep); });
        }
      };

      function escape(s) {
        return s.replace(/[&<>"]/g, function (c) {
          return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
        });
      }
      function tinted(s) {
        if (!state.punct) return escape(s);
        return s.split(PUNCT).map(function (part) {
          if (!part) return '';
          return IS_PUNCT.test(part) ? '<span class="cb-punct">' + escape(part) + '</span>' : escape(part);
        }).join('');
      }
      function overlay() {
        var el = document.getElementById('cb-word');
        if (!el) {
          el = document.createElement('div');
          el.id = 'cb-word';
          el.innerHTML = '<div class="cb-word-text"></div><div class="cb-word-count"></div>';
          document.documentElement.appendChild(el);
        }
        return el;
      }
      function render() {
        var w = list(), el = overlay();
        var text = w.length ? w[Math.min(state.word, w.length - 1)].text : '';
        var html;
        if (state.dual) {
          // Letters get the two-font pairing; punctuation stays outside it, as on the page.
          html = text.split(/([\p{L}\p{N}'’]+)/u).map(function (part) {
            if (!part) return '';
            if (!HAS_WORD.test(part)) return tinted(part);
            return '<ruby>' + tinted(part) + '<rt>' + tinted(part) + '</rt></ruby>';
          }).join('');
        } else {
          html = tinted(text);
        }
        el.firstChild.innerHTML = html;
        el.lastChild.textContent = w.length ? (state.word + 1) + ' / ' + w.length : '';
      }

      var reportTimer = null;
      function report() {
        clearTimeout(reportTimer);
        reportTimer = setTimeout(function () {
          if (!document.body) return;
          if (state.mode !== 'word') state.word = firstVisible();
          post({
            type: 'position', word: state.word, words: list().length,
            page: state.mode === 'paged' ? page : -1,
            pages: state.mode === 'paged' ? pageCount() : -1
          });
        }, 120);
      }

      function turn(step) {
        if (state.mode === 'paged') {
          var next = page + step;
          if (next < 0) { post({ type: 'edge', value: 'previous' }); return; }
          if (next >= pageCount()) { post({ type: 'edge', value: 'next' }); return; }
          setPage(next);
        } else if (state.mode === 'word') {
          var n = state.word + step;
          if (n < 0) { post({ type: 'edge', value: 'previous' }); return; }
          if (n >= list().length) { post({ type: 'edge', value: 'next' }); return; }
          state.word = n;
          render();
        }
        report();
      }

      // Taps: the outer thirds turn pages or words; anything else toggles the chrome.
      // A swipe can be followed by one synthesized click; swallow that one only.
      var swallowClickUntil = 0;
      window.cbInstallBridge = function () {
        if (window.cbBridged) return;
        window.cbBridged = true;
        document.addEventListener('click', function (e) {
          if (Date.now() < swallowClickUntil) { swallowClickUntil = 0; return; }
          for (var el = e.target; el && el.nodeType === 1; el = el.parentNode) {
            if (el.tagName === 'A' && state.mode !== 'word') return;
          }
          if (state.mode !== 'scroll') {
            var x = e.clientX / window.innerWidth;
            if (x < 0.3) { e.preventDefault(); turn(-1); return; }
            if (x > 0.7) { e.preventDefault(); turn(1); return; }
          }
          post({ type: 'tap' });
        }, true);

        var startX = 0, startY = 0;
        document.addEventListener('touchstart', function (e) {
          startX = e.touches[0].clientX;
          startY = e.touches[0].clientY;
        }, { passive: true });
        document.addEventListener('touchend', function (e) {
          if (state.mode === 'scroll') return;
          var t = e.changedTouches[0];
          var dx = t.clientX - startX, dy = t.clientY - startY;
          if (Math.abs(dx) > 45 && Math.abs(dx) > Math.abs(dy) * 1.3) {
            swallowClickUntil = Date.now() + 350;
            turn(dx < 0 ? 1 : -1);
          }
        }, { passive: true });

        var pending = false;
        window.addEventListener('scroll', function () {
          if (pending || state.mode !== 'scroll') return;
          pending = true;
          setTimeout(function () {
            pending = false;
            post({ type: 'scroll', value: window.cbScrollFraction() });
            report();
          }, 250);
        }, { passive: true });
        window.addEventListener('resize', function () {
          var keep = window.cbCurrentWord();
          if (keep !== null) window.cbAfterLayout(function () { window.cbGoToWord(keep); });
        });
      };
    })();
    """#
}
