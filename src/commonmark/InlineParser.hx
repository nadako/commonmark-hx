package commonmark;

import commonmark.Common.ENTITY;
import commonmark.Common.ESCAPABLE;
import commonmark.Common.reHtmlTag;
import commonmark.Common.normalizeURI;
import commonmark.Common.decodeHTML;
import commonmark.Common.unescapeString;

typedef InlineParserOptions = {
    var smart:Bool;
}

@:publicFields
class Delimiter {
    var cc:Int;
    var numdelims:Int;
    var node:Node;
    var previous:Delimiter;
    var previousDelimiter:Delimiter;
    var image:Bool;
    var next:Delimiter;
    var can_open:Bool;
    var can_close:Bool;
    var active:Bool;
    var index:Int;
    var bracketAfter:Bool;
    function new() {}
}

typedef Ref = {
    var destination:String;
    var title:String;
}

class InlineParser {

    static var normalizeReferenceRe = ~/[ \t\r\n]+/g;
    static function normalizeReference(s:String):String {
        s = s.substring(1, s.length - 1); // get rid of [ and ]
        s = StringTools.trim(s); // get rid of surrounding whitespace
        s = normalizeReferenceRe.replace(s, " "); // replace any whitespace with a single space
        return s.toUpperCase(); // uppercase to ignore the case
    }

    public var options:InlineParserOptions;
    var subject:String;
    var pos:Int;
    var brackets:Delimiter;
    var delimiters:Delimiter; // used by handleDelim method
    public var refmap:Map<String,Ref>;

    // Constants for character codes:

    static inline var C_ASTERISK = 42;
    static inline var C_UNDERSCORE = 95;
    static inline var C_BACKTICK = 96;
    static inline var C_OPEN_BRACKET = 91;
    static inline var C_CLOSE_BRACKET = 93;
    static inline var C_LESSTHAN = 60;
    static inline var C_BANG = 33;
    static inline var C_AMPERSAND = 38;
    static inline var C_OPEN_PAREN = 40;
    static inline var C_CLOSE_PAREN = 41;
    static inline var C_COLON = 58;
    static inline var C_SINGLEQUOTE = 39;
    static inline var C_DOUBLEQUOTE = 34;

    static var reInitialSpace = ~/^ */;
    static var reFinalSpace = ~/ *$/;
    static var reWhitespaceChar = ~/^\s/;
    static var rePunctuation =
        #if neko
        ~/^[\x{2000}-\x{206F}\x{2E00}-\x{2E7F}\\'!"#\$%&\(\)\*\+,\-\.\/:;<=>\?@\[\]\^_`\{\|\}~]/u;
        #else
        ~/^[\u2000-\u206F\u2E00-\u2E7F\\'!"#\$%&\(\)\*\+,\-\.\/:;<=>\?@\[\]\^_`\{\|\}~]/u;
        #end
    static var reEntityHere = new EReg('^' + ENTITY, 'i');
    static var reEscapable = new EReg('^' + ESCAPABLE, "");
    static var reTicks = ~/`+/;
    static var reTicksHere = ~/^`+/;
    static var reWhitespace = ~/\s+/g;
    static var reEmailAutolink = ~/^<([a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>/;
    static var reAutolink = ~/^<[A-Za-z][A-Za-z0-9.+-]{1,31}:[^<>\x00-\x20]*>/i;
    // Matches a string of non-special characters.
    static var reMain = ~/^[^\n`\[\]\\!<&*_'"]+/m;
    static var reEllipses = ~/\.\.\./g;
    static var reDash = ~/--+/g;
    static var reSpnl = ~/^ *(?:\n *)?/;
    static var ESCAPED_CHAR = '\\\\' + ESCAPABLE;
    static var reLinkTitle = new EReg(
        '^(?:"(' + ESCAPED_CHAR + '|[^"\\x00])*"' +
            '|' +
            '\'(' + ESCAPED_CHAR + '|[^\'\\x00])*\'' +
            '|' +
            '\\((' + ESCAPED_CHAR + '|[^)\\x00])*\\))', "");

    static var reLinkDestinationBraces = new EReg(
        '^(?:[<](?:[^ <>\\t\\n\\\\\\x00]' + '|' + ESCAPED_CHAR + '|' + '\\\\)*[>])', "");

    static inline var REG_CHAR = '[^\\\\()\\x00-\\x20]';
    static var IN_PARENS_NOSP = '\\((' + REG_CHAR + '|' + ESCAPED_CHAR + '|\\\\)*\\)';
    static var reLinkDestination = new EReg('^(?:' + REG_CHAR + '+|' + ESCAPED_CHAR + '|\\\\|' + IN_PARENS_NOSP + ')*', "");
    static var reLinkLabel =
        #if neko
        new EReg('^\\[(?:[^\\\\\\[\\]]|' + ESCAPED_CHAR + '|\\\\){0,700}\\]', "");
        #else
        new EReg('^\\[(?:[^\\\\\\[\\]]|' + ESCAPED_CHAR + '|\\\\){0,1000}\\]', "");
        #end

    static var reSpaceAtEndOfLine = ~/^ *(?:\n|$)/;

    public function new(?options:InlineParserOptions) {
        if (options == null)
            options = {smart: false};
        this.options = options;
        subject = "";
        pos = 0;
        refmap = new Map();
    }

    // Parse string content in block into inline children,
    // using refmap to resolve references.
    public function parse(block:Node):Void {
        subject = StringTools.trim(block.string_content);
        pos = 0;
        delimiters = null;
        brackets = null;
        while (parseInline(block)) {}
        block.string_content = null; // allow raw string to be garbage collected
        processEmphasis(null);
    }

    // Parse the next inline element in subject, advancing subject position.
    // On success, add the result to block's children and return true.
    // On failure, return false.
    function parseInline(block:Node):Bool {
        var c = peek();
        if (c == -1)
            return false;
        var res = false;
        switch(c) {
            case "\n".code:
                res = parseNewline(block);
            case "\\".code:
                res = parseBackslash(block);
            case C_BACKTICK:
                res = parseBackticks(block);
            case C_ASTERISK | C_UNDERSCORE:
                res = handleDelim(c, block);
            case C_SINGLEQUOTE | C_DOUBLEQUOTE:
                res = options.smart && handleDelim(c, block);
            case C_OPEN_BRACKET:
                res = parseOpenBracket(block);
            case C_BANG:
                res = parseBang(block);
            case C_CLOSE_BRACKET:
                res = parseCloseBracket(block);
            case C_LESSTHAN:
                res = parseAutolink(block) || parseHtmlTag(block);
            case C_AMPERSAND:
                res = parseEntity(block);
            default:
                res = parseString(block);
        }
        if (!res) {
            pos++;
            block.appendChild(text(String.fromCharCode(c)));
        }
        return true;
    }

    // Returns the code for the character at the current subject position, or -1
    // there are no more characters.
    inline function peek():Int {
        return if (pos < subject.length) subject.charCodeAt(pos) else -1;
    }

    // Parse zero or more space characters, including at most one newline
    function spnl():Bool {
        this.match(reSpnl);
        return true;
    }

    function text(s:String):Node {
        var node = new Node(Text);
        node.literal = s;
        return node;
    }

    // If re matches at current position in the subject, advance
    // position in subject and return the match; otherwise return null.
    function match(re:EReg):String {
        if (!re.match(subject.substr(pos)))
            return null;
        var p = re.matchedPos();
        pos += p.pos + p.len;
        return re.matched(0);
    }

    // Parse a newline.  If it was preceded by two spaces, return a hard
    // line break; otherwise a soft line break.
    function parseNewline(block:Node):Bool {
        pos++; // assume we're at a \n
        // check previous node for trailing spaces
        var lastc = block.lastChild;
        if (lastc != null && lastc.type == Text && lastc.literal.charAt(lastc.literal.length - 1) == ' ') {
            var hardbreak = lastc.literal.charAt(lastc.literal.length - 2) == ' ';
            lastc.literal = reFinalSpace.replace(lastc.literal, "");
            block.appendChild(new Node(hardbreak ? Linebreak : Softbreak));
        } else {
            block.appendChild(new Node(Softbreak));
        }
        match(reInitialSpace); // gobble leading spaces in next line
        return true;
    }

    // Handle a delimiter marker for emphasis or a quote.
    function handleDelim(cc:Int, block:Node):Bool {
        var res = scanDelims(cc);
        if (res == null)
            return false;

        var numdelims = res.numdelims;
        var startpos = pos;
        var contents;

        pos += numdelims;
        if (cc == C_SINGLEQUOTE)
            contents = "\u2019";
        else if (cc == C_DOUBLEQUOTE)
            contents = "\u201C";
        else
            contents = subject.substring(startpos, pos);

        var node = text(contents);
        block.appendChild(node);

        // Add entry to stack for this opener
        delimiters = {
            var d = new Delimiter();
            d.cc = cc;
            d.numdelims = numdelims;
            d.node = node;
            d.previous = delimiters;
            d.next = null;
            d.can_open = res.can_open;
            d.can_close = res.can_close;
            d.active = false;
            d;
        };

        if (delimiters.previous != null)
            delimiters.previous.next = delimiters;

        return true;
    }

    // Scan a sequence of characters with code cc, and return information about
    // the number of delimiters and whether they are positioned such that
    // they can open and/or close emphasis or strong emphasis.  A utility
    // function for strong/emph parsing.
    function scanDelims(cc:Int):{numdelims:Int, can_open:Bool, can_close:Bool} {
        var numdelims = 0;
        var startpos = pos;

        if (cc == C_SINGLEQUOTE || cc == C_DOUBLEQUOTE) {
            numdelims++;
            pos++;
        } else {
            while (peek() == cc) {
                numdelims++;
                pos++;
            }
        }

        if (numdelims == 0)
            return null;

        var char_before = startpos == 0 ? '\n' : subject.charAt(startpos - 1);

        var cc_after = peek();
        var char_after;
        if (cc_after == -1)
            char_after = '\n';
        else
            char_after = String.fromCharCode(cc_after);

        var after_is_whitespace = reWhitespaceChar.match(char_after);
        var after_is_punctuation = rePunctuation.match(char_after);
        var before_is_whitespace = reWhitespaceChar.match(char_before);
        var before_is_punctuation = rePunctuation.match(char_before);

        var left_flanking = !after_is_whitespace && !(after_is_punctuation && !before_is_whitespace && !before_is_punctuation);
        var right_flanking = !before_is_whitespace && !(before_is_punctuation && !after_is_whitespace && !after_is_punctuation);
        var can_open, can_close;
        if (cc == C_UNDERSCORE) {
            can_open = left_flanking && (!right_flanking || before_is_punctuation);
            can_close = right_flanking && (!left_flanking || after_is_punctuation);
        } else if (cc == C_SINGLEQUOTE || cc == C_DOUBLEQUOTE) {
            can_open = left_flanking && !right_flanking;
            can_close = right_flanking;
        } else {
            can_open = left_flanking;
            can_close = right_flanking;
        }
        pos = startpos;
        return {numdelims: numdelims, can_open: can_open, can_close: can_close};
    }

    // Attempt to parse an entity.
    function parseEntity(block:Node):Bool {
        var m = match(reEntityHere);
        if (m != null) {
            block.appendChild(text(decodeHTML(m)));
            return true;
        } else {
            return false;
        }
    }

    // Parse a backslash-escaped special character, adding either the escaped
    // character, a hard line break (if the backslash is followed by a newline),
    // or a literal backslash to the block's children.  Assumes current character
    // is a backslash.
    function parseBackslash(block:Node):Bool {
        var subj = subject;
        pos++;
        if (peek() == "\n".code) {
            pos++;
            block.appendChild(new Node(Linebreak));
        } else if (reEscapable.match(subj.charAt(pos))) {
            block.appendChild(text(subj.charAt(pos)));
            pos++;
        } else {
            block.appendChild(text('\\'));
        }
        return true;
    }

    // Attempt to parse backticks, adding either a backtick code span or a
    // literal sequence of backticks.
    function parseBackticks(block:Node):Bool {
        var ticks = match(reTicksHere);
        if (ticks == null)
            return false;

        var afterOpenTicks = pos;
        var matched;
        while ((matched = match(reTicks)) != null) {
            if (matched == ticks) {
                var node = new Node(Code);
                node.literal = reWhitespace.replace(StringTools.trim(subject.substring(afterOpenTicks, pos - ticks.length)), ' ');
                block.appendChild(node);
                return true;
            }
        }
        // If we got here, we didn't match a closing backtick sequence.
        pos = afterOpenTicks;
        block.appendChild(text(ticks));
        return true;
    }

    // Attempt to parse a raw HTML tag.
    function parseHtmlTag(block:Node):Bool {
        var m = match(reHtmlTag);
        if (m == null)
            return false;
        var node = new Node(HtmlInline);
        node.literal = m;
        block.appendChild(node);
        return true;
    }

    // IF next character is [, and ! delimiter to delimiter stack and
    // add a text node to block's children.  Otherwise just add a text node.
    function parseBang(block:Node):Bool {
        var startpos = pos;
        pos++;
        if (peek() == C_OPEN_BRACKET) {
            pos++;

            var node = text('![');
            block.appendChild(node);

            // Add entry to stack for this opener
            addBracket(node, startpos + 1, true);
        } else {
            block.appendChild(text('!'));
        }
        return true;
    }

    // Add open bracket to delimiter stack and add a text node to block's children.
    function parseOpenBracket(block:Node):Bool {
        var startpos = pos;
        pos++;

        var node = text('[');
        block.appendChild(node);

        // Add entry to stack for this opener
        addBracket(node, startpos, false);
        return true;
    }

    function addBracket(node:Node, index:Int, image:Bool) {
        if (brackets != null)
            brackets.bracketAfter = true;

        var d = new Delimiter();
        d.node = node;
        d.previous = brackets;
        d.previousDelimiter = delimiters;
        d.index = index;
        d.image = image;
        d.active = true;
        brackets = d;
    }

    inline function removeBracket() {
        brackets = brackets.previous;
    }

    // Attempt to parse an autolink (URL or email in pointy brackets).
    function parseAutolink(block:Node):Bool {
        var m;
        if ((m = match(reEmailAutolink)) != null) {
            var dest = m.substring(1, m.length - 1);
            var node = new Node(Link);
            node.destination = normalizeURI('mailto:' + dest);
            node.title = '';
            node.appendChild(text(dest));
            block.appendChild(node);
            return true;
        } else if ((m = this.match(reAutolink)) != null) {
            var dest = m.substring(1, m.length - 1);
            var node = new Node(Link);
            node.destination = normalizeURI(dest);
            node.title = '';
            node.appendChild(text(dest));
            block.appendChild(node);
            return true;
        } else {
            return false;
        }
    }

    // Parse a run of ordinary characters, or a single character with
    // a special meaning in markdown, as a plain string.
    function parseString(block:Node):Bool {
        var m = match(reMain);
        if (m == null)
            return false;
        if (options.smart) {
            m = reEllipses.replace(m, "\u2026");
            m = reDash.map(m, function(r) {
                var chars = r.matched(0);
                var enCount = 0;
                var emCount = 0;
                if (chars.length % 3 == 0) { // If divisible by 3, use all em dashes
                    emCount = Std.int(chars.length / 3);
                } else if (chars.length % 2 == 0) { // If divisible by 2, use all en dashes
                    enCount = Std.int(chars.length / 2);
                } else if (chars.length % 3 == 2) { // If 2 extra dashes, use en dash for last 2; em dashes for rest
                    enCount = 1;
                    emCount = Std.int((chars.length - 2) / 3);
                } else { // Use en dashes for last 4 hyphens; em dashes for rest
                    enCount = 2;
                    emCount = Std.int((chars.length - 4) / 3);
                }
                var s = new StringBuf();
                for (_ in 0...emCount)
                    s.add("\u2014");
                for (_ in 0...enCount)
                    s.add("\u2013");
                return s.toString();
            });
            block.appendChild(text(m));
        } else {
            block.appendChild(text(m));
        }
        return true;
    }

    // Try to match close bracket against an opening in the delimiter
    // stack.  Add either a link or image, or a plain [ character,
    // to block's children.  If there is a matching delimiter,
    // remove it from the delimiter stack.
    function parseCloseBracket(block:Node):Bool {
        pos++;
        var startpos = pos;

        // get last [ or ![
        var opener = brackets;

        if (opener == null) {
            // no matched opener, just return a literal
            block.appendChild(text(']'));
            return true;
        }

        if (!opener.active) {
            // no matched opener, just return a literal
            block.appendChild(text(']'));
            // take opener off brackets stack
            removeBracket();
            return true;
        }

        // If we got here, open is a potential opener
        var is_image = opener.image;

        // Check to see if we have a link/image

        // Inline link?
        var matched = false;
        var dest = null, title = null;
        if (peek() == C_OPEN_PAREN) {
            pos++;
            if (spnl() &&
                ((dest = parseLinkDestination()) != null) &&
                spnl() &&
                // make sure there's a space before the title:
                (reWhitespaceChar.match(subject.charAt(pos - 1)) &&
                 (title = parseLinkTitle()) != null || true) &&
                spnl() &&
                peek() == C_CLOSE_PAREN) {
                pos++;
                matched = true;
            }
        } else {
            // Next, see if there's a link label
            var savepos = pos;
            var beforelabel = pos;
            var reflabel = null;
            var n = parseLinkLabel();
            if (n > 2) {
                reflabel = subject.substring(beforelabel, beforelabel + n);
            } else if (!opener.bracketAfter) {
                // Empty or missing second label means to use the first label as the reference.
                // The reference must not contain a bracket. If we know there's a bracket, we don't even bother checking it.
                reflabel = subject.substring(opener.index, startpos);
            }
            if (n == 0) {
                // If shortcut reference link, rewind before spaces we skipped.
                pos = savepos;
            }

            if (reflabel != null || reflabel.length > 0) {
                // lookup rawlabel in refmap
                var link = refmap[normalizeReference(reflabel)];
                if (link != null) {
                    dest = link.destination;
                    title = link.title;
                    matched = true;
                }
            }
        }

        if (matched) {
            var node = new Node(is_image ? Image : Link);
            node.destination = dest;
            node.title = title != null ? title : '';

            var tmp = opener.node.next, next;
            while (tmp != null) {
                next = tmp.next;
                tmp.unlink();
                node.appendChild(tmp);
                tmp = next;
            }
            block.appendChild(node);
            processEmphasis(opener.previousDelimiter);
            removeBracket();
            opener.node.unlink();

            // We remove this bracket and processEmphasis will remove later delimiters.
            // Now, for a link, we also deactivate earlier link openers.
            // (no links in links)
            if (!is_image) {
              opener = brackets;
              while (opener != null) {
                if (!opener.image) {
                    opener.active = false; // deactivate this opener
                }
                opener = opener.previous;
              }
            }

            return true;
        } else { // no match
            removeBracket();  // remove this opener from stack
            pos = startpos;
            block.appendChild(text(']'));
            return true;
        }
    }

    // Attempt to parse link title (sans quotes), returning the string
    // or null if no match.
    function parseLinkTitle():String {
        var title = match(reLinkTitle);
        if (title == null)
            return null;
        // chop off quotes from title and unescape:
        return unescapeString(title.substr(1, title.length - 2));
    }

    function removeDelimiter(delim:Delimiter):Void {
        if (delim.previous != null)
            delim.previous.next = delim.next;
        if (delim.next == null)
            delimiters = delim.previous;
        else
            delim.next.previous = delim.previous;
    }

    // Attempt to parse link destination, returning the string or
    // null if no match.
    function parseLinkDestination():String {
        var res = match(reLinkDestinationBraces);
        if (res == null) {
            res = match(reLinkDestination);
            if (res == null) {
                return null;
            } else {
                return normalizeURI(unescapeString(res));
            }
        } else {  // chop off surrounding <..>:
            return normalizeURI(unescapeString(res.substr(1, res.length - 2)));
        }
    }

    // Attempt to parse a link label, returning number of characters parsed.
    function parseLinkLabel():Int {
        var m = match(reLinkLabel);
        if (m == null || m.length > #if neko 701 #else 1001 #end)
            return 0;
        else
            return m.length;
    }

    function processEmphasis(stack_bottom:Delimiter):Void {
        var openers_bottom = [
            C_UNDERSCORE => stack_bottom,
            C_ASTERISK => stack_bottom,
            C_SINGLEQUOTE => stack_bottom,
            C_DOUBLEQUOTE => stack_bottom,
        ];
        var odd_match = false;

        // find first closer above stack_bottom:
        var closer = delimiters;
        while (closer != null && closer.previous != stack_bottom)
            closer = closer.previous;

        // move forward, looking for closers, and handling each
        while (closer != null) {
            var closercc = closer.cc;
            if (!closer.can_close) {
                closer = closer.next;
            } else {
                // found emphasis closer. now look back for first matching opener:
                var opener = closer.previous;
                var opener_found = false;
                while (opener != null && opener != stack_bottom && opener != openers_bottom[closercc]) {
                    odd_match = (closer.can_open || opener.can_close) && (opener.numdelims + closer.numdelims) % 3 == 0;
                    if (opener.cc == closer.cc && opener.can_open && !odd_match) {
                        opener_found = true;
                        break;
                    }
                    opener = opener.previous;
                }
                var old_closer = closer;

                if (closercc == C_ASTERISK || closercc == C_UNDERSCORE) {
                    if (!opener_found) {
                        closer = closer.next;
                    } else {
                        // calculate actual number of delimiters used from closer
                        var use_delims;
                        if (closer.numdelims < 3 || opener.numdelims < 3)
                            use_delims = closer.numdelims <= opener.numdelims ? closer.numdelims : opener.numdelims;
                        else
                            use_delims = closer.numdelims % 2 == 0 ? 2 : 1;

                        var opener_inl = opener.node;
                        var closer_inl = closer.node;

                        // remove used delimiters from stack elts and inlines
                        opener.numdelims -= use_delims;
                        closer.numdelims -= use_delims;
                        opener_inl.literal = opener_inl.literal.substring(0, opener_inl.literal.length - use_delims);
                        closer_inl.literal = closer_inl.literal.substring(0, closer_inl.literal.length - use_delims);

                        // build contents for new emph element
                        var emph = new Node(use_delims == 1 ? Emph : Strong);

                        var tmp = opener_inl.next;
                        while (tmp != null && tmp != closer_inl) {
                            var next = tmp.next;
                            tmp.unlink();
                            emph.appendChild(tmp);
                            tmp = next;
                        }

                        opener_inl.insertAfter(emph);

                        // remove elts between opener and closer in delimiters stack
                        removeDelimitersBetween(opener, closer);

                        // if opener has 0 delims, remove it and the inline
                        if (opener.numdelims == 0) {
                            opener_inl.unlink();
                            removeDelimiter(opener);
                        }

                        if (closer.numdelims == 0) {
                            closer_inl.unlink();
                            var tempstack = closer.next;
                            removeDelimiter(closer);
                            closer = tempstack;
                        }
                    }

                } else if (closercc == C_SINGLEQUOTE) {
                    closer.node.literal = "\u2019";
                    if (opener_found)
                        opener.node.literal = "\u2018";
                    closer = closer.next;
                } else if (closercc == C_DOUBLEQUOTE) {
                    closer.node.literal = "\u201D";
                    if (opener_found)
                        opener.node.literal = "\u201C";
                    closer = closer.next;
                }
                if (!opener_found && !odd_match) {
                    // Set lower bound for future searches for openers:
                    // We don't do this with odd_match because a **
                    // that doesn't match an earlier * might turn into
                    // an opener, and the * might be matched by something
                    // else.
                    openers_bottom[closercc] = old_closer.previous;
                    if (!old_closer.can_open) {
                        // We can remove a closer that can't be an opener,
                        // once we've seen there's no matching opener:
                        removeDelimiter(old_closer);
                    }
                }
            }
        }

        // remove all delimiters
        while (delimiters != null && delimiters != stack_bottom)
            removeDelimiter(delimiters);
    }

    function removeDelimitersBetween(bottom:Delimiter, top:Delimiter):Void {
        if (bottom.next != top) {
            bottom.next = top;
            top.previous = bottom;
        }
    }

    // Attempt to parse a link reference, modifying refmap.
    public function parseReference(s:String, refmap:Map<String,Ref>) {
        subject = s;
        pos = 0;

        var startpos = pos;

        // label:
        var rawlabel;
        var matchChars = parseLinkLabel();
        if (matchChars == 0)
            return 0;
        else
            rawlabel = subject.substr(0, matchChars);

        // colon:
        if (this.peek() == C_COLON) {
            pos++;
        } else {
            pos = startpos;
            return 0;
        }

        //  link url
        spnl();

        var dest = parseLinkDestination();
        if (dest == null || dest.length == 0) {
            pos = startpos;
            return 0;
        }

        var beforetitle = pos;
        spnl();
        var title = parseLinkTitle();
        if (title == null) {
            title = '';
            // rewind before spaces
            pos = beforetitle;
        }

        // make sure we're at line end:
        var atLineEnd = true;
        if (match(reSpaceAtEndOfLine) == null) {
            if (title == '') {
                atLineEnd = false;
            } else {
                // the potential title we found is not at the line end,
                // but it could still be a legal link reference if we
                // discard the title
                title = '';
                // rewind before spaces
                pos = beforetitle;
                // and instead check if the link URL is at the line end
                atLineEnd = match(reSpaceAtEndOfLine) != null;
            }
        }

        if (!atLineEnd) {
            pos = startpos;
            return 0;
        }

        var normlabel = normalizeReference(rawlabel);
        if (normlabel == '') {
            // label must contain non-whitespace characters
            pos = startpos;
            return 0;
        }

        if (!refmap.exists(normlabel))
            refmap[normlabel] = {destination: dest, title: title};

        return this.pos - startpos;
    }
}
