package cmark;

import cmark.Common.unescapeString;
import cmark.Common.OPENTAG;
import cmark.Common.CLOSETAG;
import cmark.Node.ListData;
import cmark.Node.NodeType;

typedef ParserOptions = {
    >InlineParser.InlineParserOptions,
}

interface IBlockBehaviour {
    function doContinue(parser:Parser, block:Node):Int;
    function finalize(parser:Parser, block:Node):Void;
    function canContain(t:NodeType):Bool;
    function acceptsLines():Bool;
}

@:publicFields
class DocumentBehaviour implements IBlockBehaviour {
    function new() {}
    function doContinue(_, _) return 0;
    function finalize(_, _) {};
    function canContain(t:NodeType) return (t != Item);
    function acceptsLines() return false;
}

@:publicFields
@:access(cmark.Parser)
class ListBehaviour implements IBlockBehaviour {
    function new() {}
    function doContinue(_, _) return 0;
    function finalize(parser:Parser, block:Node) {
        var item = block.firstChild;
        while (item != null) {
            // check for non-final list item ending with blank line:
            if (Parser.endsWithBlankLine(item) && item.next != null) {
                block.listData.tight = false;
                break;
            }
            // recurse into children of list item, to see if there are
            // spaces between any of them:
            var subitem = item.firstChild;
            while (subitem != null) {
                if (Parser.endsWithBlankLine(subitem) && (item.next != null || subitem.next != null)) {
                    block.listData.tight = false;
                    break;
                }
                subitem = subitem.next;
            }
            item = item.next;
        }
    }
    function canContain(t:NodeType) return (t == Item);
    function acceptsLines() return false;
}

@:publicFields
@:access(cmark.Parser)
class BlockQuoteBehaviour implements IBlockBehaviour {
    function new() {}
    function doContinue(parser:Parser, _) {
        var ln = parser.currentLine;
        if (!parser.indented && Parser.peek(ln, parser.nextNonspace) == Parser.C_GREATERTHAN) {
            parser.advanceNextNonspace();
            parser.advanceOffset(1, false);
            if (Parser.peek(ln, parser.offset) == Parser.C_SPACE)
                parser.offset++;
        } else {
            return 1;
        }
        return 0;
    }
    function finalize(_, _) {};
    function canContain(t:NodeType) return (t != Item);
    function acceptsLines() return false;
}

@:publicFields
@:access(cmark.Parser)
class ItemBehaviour implements IBlockBehaviour {
    function new() {}
    function doContinue(parser:Parser, container:Node) {
        if (parser.blank && container.firstChild != null) {
            parser.advanceNextNonspace();
        } else if (parser.indent >= container.listData.markerOffset + container.listData.padding) {
            parser.advanceOffset(container.listData.markerOffset + container.listData.padding, true);
        } else {
            return 1;
        }
        return 0;
    }
    function finalize(_, _) {}
    function canContain(t:NodeType) return (t != Item);
    function acceptsLines() return false;
}

@:publicFields
class HeaderBehaviour implements IBlockBehaviour {
    function new() {}
    function doContinue(_, _) {
        // a header can never container > 1 line, so fail to match:
        return 1;
    }
    function finalize(_, _) {};
    function canContain(_) return false;
    function acceptsLines() return false;
}

@:publicFields
class HorizontalRuleBehaviour implements IBlockBehaviour {
    function new() {}
    function doContinue(_, _) {
        // an hrule can never container > 1 line, so fail to match:
        return 1;
    };
    function finalize(_, _) {};
    function canContain(_) return false;
    function acceptsLines() return false;
}

@:publicFields
@:access(cmark.Parser)
class CodeBlockBehaviour implements IBlockBehaviour {
    function new() {}
    function doContinue(parser:Parser, container:Node) {
        var ln = parser.currentLine;
        var indent = parser.indent;
        if (container.isFenced) { // fenced
            var match = indent <= 3 && ln.charAt(parser.nextNonspace) == container.fenceChar && Parser.reClosingCodeFence.match(ln.substr(parser.nextNonspace));
            if (match && Parser.reClosingCodeFence.matched(0).length >= container.fenceLength) {
                // closing fence - we're at end of line, so we can return
                parser.finalize(container, parser.lineNumber);
                return 2;
            } else {
                // skip optional spaces of fence offset
                var i = container.fenceOffset;
                while (i > 0 && Parser.peek(ln, parser.offset) == Parser.C_SPACE) {
                    parser.advanceOffset(1, false);
                    i--;
                }
            }
        } else { // indented
            if (indent >= Parser.CODE_INDENT) {
                parser.advanceOffset(Parser.CODE_INDENT, true);
            } else if (parser.blank) {
                parser.advanceNextNonspace();
            } else {
                return 1;
            }
        }
        return 0;
    }
    function finalize(parser:Parser, block:Node) {
        if (block.isFenced) { // fenced
            // first line becomes info string
            var content = block.string_content;
            var newlinePos = content.indexOf('\n');
            var firstLine = content.substring(0, newlinePos);
            var rest = content.substr(newlinePos + 1);
            block.info = unescapeString(StringTools.trim(firstLine));
            block.literal = rest;
        } else { // indented
            block.literal = ~/(\n *)+$/.replace(block.string_content, '\n');
        }
        block.string_content = null; // allow GC
    }
    function canContain(_) return false;
    function acceptsLines() return true;
}

@:publicFields
@:access(cmark.Parser)
class HtmlBlockBehaviour implements IBlockBehaviour {
    function new() {}
    function doContinue(parser:Parser, container:Node) {
        return ((parser.blank && (container.htmlBlockType == 6 || container.htmlBlockType == 7)) ? 1 : 0);
    }
    function finalize(parser:Parser, block:Node) {
        block.literal = ~/(\n *)+$/.replace(block.string_content, '');
        block.string_content = null; // allow GC
    }
    function canContain(_) return false;
    function acceptsLines() return true;
}

@:publicFields
@:access(cmark.Parser)
class ParagraphBehaviour implements IBlockBehaviour {
    function new() {}
    function doContinue(parser:Parser, _) {
        return (parser.blank ? 1 : 0);
    }
    function finalize(parser:Parser, block:Node) {
        var pos;
        var hasReferenceDefs = false;

        // try parsing the beginning as link reference definitions:
        while (Parser.peek(block.string_content, 0) == Parser.C_OPEN_BRACKET && (pos = parser.inlineParser.parseReference(block.string_content, parser.refmap)) != 0) {
            block.string_content = block.string_content.substr(pos);
            hasReferenceDefs = true;
        }
        if (hasReferenceDefs && Parser.isBlank(block.string_content)) {
            block.unlink();
        }
    }
    function canContain(_) return false;
    function acceptsLines() return true;
}

class Parser {
    var doc:Node;
    var inlineParser:InlineParser;
    var tip:Node;
    var oldtip:Node;
    var currentLine:String;
    var lineNumber:Int;
    var offset:Int;
    var column:Int;
    var nextNonspace:Int;
    var nextNonspaceColumn:Int;
    var indent:Int;
    var indented:Bool;
    var blank:Bool;
    var allClosed:Bool;
    var lastMatchedContainer:Node;
    var lastLineLength:Int;
    var refmap:Map<String,InlineParser.Ref>;
    var options:ParserOptions;

    static inline var CODE_INDENT = 4;    

    static inline var C_NEWLINE = 10;
    static inline var C_GREATERTHAN = 62;
    static inline var C_LESSTHAN = 60;
    static inline var C_SPACE = 32;
    static inline var C_OPEN_BRACKET = 91;

    static var reLineEnding = ~/\r\n|\n|\r/g;
    static var reMaybeSpecial = ~/^[#`~*+_=<>0-9-]/;
    static var reHtmlBlockOpen = [
        ~/./, // dummy for 0
        ~/^<(?:script|pre|style)(?:\s|>|$)/i,
        ~/^<!--/,
        ~/^<[?]/,
        ~/^<![A-Z]/,
        ~/^<!\[CDATA\[/,
        ~/^<[\/]?(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h1|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|meta|nav|noframes|ol|optgroup|option|p|param|section|source|title|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:\s|[\/]?[>]|$)/i,
        new EReg('^(?:' + OPENTAG + '|' + CLOSETAG + ')\\s*$', 'i')
    ];
    static var reHtmlBlockClose = [
        ~/./, // dummy for 0
        ~/<\/(?:script|pre|style)>/i,
        ~/-->/,
        ~/\?>/,
        ~/>/,
        ~/\]\]>/
    ];
    static var reATXHeaderMarker = ~/^#{1,6}(?: +|$)/;
    static var reCodeFence = ~/^`{3,}(?!.*`)|^~{3,}(?!.*~)/;
    static var reClosingCodeFence = ~/^(?:`{3,}|~{3,})(?= *$)/;
    static var reSetextHeaderLine = ~/^(?:=+|-+) *$/;
    static var reHrule = ~/^(?:(?:\* *){3,}|(?:_ *){3,}|(?:- *){3,}) *$/;
    static var reBulletListMarker = ~/^[*+-]( +|$)/;
    static var reOrderedListMarker = ~/^(\d{1,9})([.)])( +|$)/;
    static var reNonSpace = ~/[^ \t\r\n]/;

    static function peek(ln:String, pos:Int):Int {
        if (pos < ln.length)
            return ln.charCodeAt(pos);
        else
            return -1;
    }

    // Returns true if string contains only space characters.
    static inline function isBlank(s:String):Bool {
        return !(reNonSpace.match(s));
    }

    // 'finalize' is run when the block is closed.
    // 'doContinue' is run to check whether the block is continuing
    // at a certain line and offset (e.g. whether a block quote
    // contains a `>`.  It returns 0 for matched, 1 for not matched,
    // and 2 for "we've dealt with this line completely, go to next."
    var blocks:Map<NodeType,IBlockBehaviour> = [
        Document => new DocumentBehaviour(),
        List => new ListBehaviour(),
        BlockQuote => new BlockQuoteBehaviour(),
        Item => new ItemBehaviour(),
        Header => new HeaderBehaviour(),
        HorizontalRule => new HorizontalRuleBehaviour(),
        CodeBlock => new CodeBlockBehaviour(),
        HtmlBlock => new HtmlBlockBehaviour(),
        Paragraph => new ParagraphBehaviour(),
    ];

    // block start functions.  Return values:
    // 0 = no match
    // 1 = matched container, keep going
    // 2 = matched leaf, no more block starts
    static var blockStarts:Array<Parser->Node->Int> = [
        // block quote
        function(parser:Parser, container:Node):Int {
            if (!parser.indented && peek(parser.currentLine, parser.nextNonspace) == C_GREATERTHAN) {
                parser.advanceNextNonspace();
                parser.advanceOffset(1, false);
                // optional following space
                if (peek(parser.currentLine, parser.offset) == C_SPACE)
                    parser.advanceOffset(1, false);
                parser.closeUnmatchedBlocks();
                parser.addChild(BlockQuote, parser.nextNonspace);
                return 1;
            } else {
                return 0;
            }
        },

        // ATX header
        function(parser:Parser, container:Node):Int {
            if (!parser.indented && (reATXHeaderMarker.match(parser.currentLine.substring(parser.nextNonspace)))) {
                parser.advanceNextNonspace();
                parser.advanceOffset(reATXHeaderMarker.matched(0).length, false);
                parser.closeUnmatchedBlocks();
                var container = parser.addChild(Header, parser.nextNonspace);
                container.level = StringTools.trim(reATXHeaderMarker.matched(0)).length; // number of #s
                // remove trailing ###s:
                container.string_content = ~/ +#+ *$/.replace(~/^ *#+ *$/.replace(parser.currentLine.substr(parser.offset), ''), '');
                parser.advanceOffset(parser.currentLine.length - parser.offset);
                return 2;
            } else {
                return 0;
            }
        },

        // Fenced code block
        function(parser:Parser, container:Node):Int {
            if (!parser.indented && reCodeFence.match(parser.currentLine.substr(parser.nextNonspace))) {
                var fenceLength = reCodeFence.matched(0).length;
                parser.closeUnmatchedBlocks();
                var container = parser.addChild(CodeBlock, parser.nextNonspace);
                container.isFenced = true;
                container.fenceLength = fenceLength;
                container.fenceChar = reCodeFence.matched(0).charAt(0);
                container.fenceOffset = parser.indent;
                parser.advanceNextNonspace();
                parser.advanceOffset(fenceLength, false);
                return 2;
            } else {
                return 0;
            }
        },

        // HTML block
        function(parser:Parser, container:Node):Int {
            if (!parser.indented && peek(parser.currentLine, parser.nextNonspace) == C_LESSTHAN) {
                var s = parser.currentLine.substr(parser.nextNonspace);
                for (blockType in 1...8) {
                    if (reHtmlBlockOpen[blockType].match(s) && (blockType < 7 || container.type != Paragraph)) {
                        parser.closeUnmatchedBlocks();
                        // We don't adjust parser.offset;
                        // spaces are part of the HTML block:
                        var b = parser.addChild(HtmlBlock, parser.offset);
                        b.htmlBlockType = blockType;
                        return 2;
                    }
                }
            }
            return 0;
        },

        // Setext header
        function(parser:Parser, container:Node):Int {
            if (!parser.indented && container.type == Paragraph && (container.string_content.indexOf('\n') == container.string_content.length - 1) && (reSetextHeaderLine.match(parser.currentLine.substring(parser.nextNonspace)))) {
                parser.closeUnmatchedBlocks();
                var header = new Node(Header, container.sourcepos);
                header.level = reSetextHeaderLine.matched(0).charAt(0) == '=' ? 1 : 2;
                header.string_content = container.string_content;
                container.insertAfter(header);
                container.unlink();
                parser.tip = header;
                parser.advanceOffset(parser.currentLine.length - parser.offset, false);
                return 2;
            } else {
                return 0;
            }
        },

        // hrule
        function(parser:Parser, container:Node):Int {
            if (!parser.indented && reHrule.match(parser.currentLine.substr(parser.nextNonspace))) {
                parser.closeUnmatchedBlocks();
                parser.addChild(HorizontalRule, parser.nextNonspace);
                parser.advanceOffset(parser.currentLine.length - parser.offset, false);
                return 2;
            } else {
                return 0;
            }
        },

        // list item
        function(parser:Parser, container:Node):Int {
            var data = parseListMarker(parser.currentLine, parser.nextNonspace, parser.indent);
            if (data != null && (!parser.indented || container.type == List)) {
                parser.closeUnmatchedBlocks();
                parser.advanceNextNonspace();
                // recalculate data.padding, taking into account tabs:
                var i = parser.column;
                parser.advanceOffset(data.padding, false);
                data.padding = parser.column - i;

                // add the list if needed
                if (parser.tip.type != List || !(listsMatch(container.listData, data))) {
                    container = parser.addChild(List, parser.nextNonspace);
                    container.listData = data;
                }

                // add the list item
                container = parser.addChild(Item, parser.nextNonspace);
                container.listData = data;
                return 1;
            } else {
                return 0;
            }
        },

        // indented code block
        function(parser:Parser, container:Node):Int {
            if (parser.indented && parser.tip.type != Paragraph && !parser.blank) {
                // indented code
                parser.advanceOffset(CODE_INDENT, true);
                parser.closeUnmatchedBlocks();
                parser.addChild(CodeBlock, parser.offset);
                return 2;
            } else {
                return 0;
            }
         }

    ];

    public function new(?options:ParserOptions) {
        if (options == null)
            options = {smart: false};
        this.options = options;

        inlineParser = new InlineParser(options);
        doc = newDocument();
        tip = doc;
        oldtip = doc;
        currentLine = "";
        lineNumber = 0;
        offset = 0;
        column = 0;
        nextNonspace = 0;
        nextNonspaceColumn = 0;
        indent = 0;
        indented = false;
        blank = false;
        allClosed = true;
        lastMatchedContainer = doc;
        refmap = new Map();
        lastLineLength = 0;
    }

    inline function newDocument() return new Node(Document, [[1, 1], [0, 0]]);

    // The main parsing function.  Returns a parsed document AST.
    public function parse(input:String):Node {
        doc = newDocument();
        tip = doc;
        refmap = new Map();
        lineNumber = 0;
        lastLineLength = 0;
        offset = 0;
        column = 0;
        lastMatchedContainer = doc;
        currentLine = "";
        var lines = reLineEnding.split(input);
        var len = lines.length;
        if (input.charCodeAt(input.length - 1) == C_NEWLINE)
            // ignore last blank line created by final newline
            len--;
        for (i in 0...len)
            incorporateLine(lines[i]);
        while (tip != null)
            finalize(tip, len);
        processInlines(doc);
        return doc;
    }

    // Analyze a line of text and update the document appropriately.
    // We parse markdown text by calling this on each line of input,
    // then finalizing the document.
    function incorporateLine(ln:String):Void {
        var all_matched = true;

        var container = doc;
        oldtip = tip;
        offset = 0;
        lineNumber += 1;

        // replace NUL characters for security
        if (ln.indexOf('\u0000') != -1)
            ln = ~/\0/g.replace(ln, '\uFFFD');

        currentLine = ln;

        // For each containing block, try to parse the associated line start.
        // Bail out on failure: container will point to the last matching block.
        // Set all_matched to false if not all containers match.
        var lastChild;
        while ((lastChild = container.lastChild) != null && lastChild.open) {
            container = lastChild;

            findNextNonspace();

            switch (blocks[container.type].doContinue(this, container)) {
                case 0: // we've matched, keep going
                case 1: // we've failed to match a block
                    all_matched = false;
                case 2: // we've hit end of line for fenced code close and can return
                    lastLineLength = ln.length;
                    return;
                default:
                    throw 'continue returned illegal value, must be 0, 1, or 2';
            }
            if (!all_matched) {
                container = container.parent; // back up to last matching block
                break;
            }
        }

        allClosed = (container == oldtip);
        lastMatchedContainer = container;

        // Check to see if we've hit 2nd blank line; if so break out of list:
        if (blank && container.lastLineBlank)
            breakOutOfLists(container);

        var matchedLeaf = container.type != Paragraph && blocks[container.type].acceptsLines();
        var starts = blockStarts;
        var startsLen = starts.length;
        // Unless last matched container is a code block, try new container starts,
        // adding children to the last matched container:
        while (!matchedLeaf) {
            findNextNonspace();

            // this is a little performance optimization:
            if (!indented && !reMaybeSpecial.match(ln.substring(nextNonspace))) {
                advanceNextNonspace();
                break;
            }

            var i = 0;
            while (i < startsLen) {
                var res = starts[i](this, container);
                if (res == 1) {
                    container = tip;
                    break;
                } else if (res == 2) {
                    container = tip;
                    matchedLeaf = true;
                    break;
                } else {
                    i++;
                }
            }

            if (i == startsLen) { // nothing matched
                advanceNextNonspace();
                break;
            }
        }

        // What remains at the offset is a text line.  Add the text to the
        // appropriate container.

        // First check for a lazy paragraph continuation:
        if (!allClosed && !blank && tip.type == Paragraph) {
            // lazy paragraph continuation
            addLine();

        } else { // not a lazy continuation

            // finalize any blocks not matched
            closeUnmatchedBlocks();
            if (blank && container.lastChild != null)
                container.lastChild.lastLineBlank = true;

            var t = container.type;

            // Block quote lines are never blank as they start with >
            // and we don't count blanks in fenced code for purposes of tight/loose
            // lists or breaking out of lists.  We also don't set _lastLineBlank
            // on an empty list item, or if we just closed a fenced block.
            var lastLineBlank = blank && !(t == BlockQuote || (t == CodeBlock && container.isFenced) || (t == Item && container.firstChild == null && container.sourcepos[0][0] == this.lineNumber));

            // propagate lastLineBlank up through parents:
            var cont = container;
            while (cont != null) {
                cont.lastLineBlank = lastLineBlank;
                cont = cont.parent;
            }

            if (blocks[t].acceptsLines()) {
                addLine();
                // if HtmlBlock, check for end condition
                if (t == HtmlBlock && container.htmlBlockType >= 1 && container.htmlBlockType <= 5 && reHtmlBlockClose[container.htmlBlockType].match(currentLine.substring(offset)))
                    finalize(container, lineNumber);

            } else if (offset < ln.length && !blank) {
                // create paragraph container for line
                container = this.addChild(Paragraph, this.offset);
                this.advanceNextNonspace();
                this.addLine();
            }
        }
        lastLineLength = ln.length;
    }

    // Finalize a block.  Close it and do any necessary postprocessing,
    // e.g. creating string_content from strings, setting the 'tight'
    // or 'loose' status of a list, and parsing the beginnings
    // of paragraphs for reference definitions.  Reset the tip to the
    // parent of the closed block.
    function finalize(block:Node, lineNumber:Int):Void {
        var above = block.parent;
        block.open = false;
        block.sourcepos[1] = [lineNumber, lastLineLength];
        blocks[block.type].finalize(this, block);
        tip = above;
    }

    // Walk through a block & children recursively, parsing string content
    // into inline content where appropriate.
    function processInlines(block:Node):Void {
        inlineParser.refmap = refmap;
        inlineParser.options = options;
        var walker = block.walker();
        var event;
        while ((event = walker.next()) != null) {
            var node = event.node;
            var t = node.type;
            if (!event.entering && (t == Paragraph || t == Header))
                inlineParser.parse(node);
        }
    }

    function findNextNonspace():Void {
        var currentLine = this.currentLine;
        var i = this.offset;
        var cols = this.column;
        var c;

        while ((c = currentLine.charAt(i)) != '') {
            if (c == ' ') {
                i++;
                cols++;
            } else if (c == '\t') {
                i++;
                cols += (4 - (cols % 4));
            } else {
                break;
            }
        }
        this.blank = (c == '\n' || c == '\r' || c == '');
        this.nextNonspace = i;
        this.nextNonspaceColumn = cols;
        this.indent = this.nextNonspaceColumn - this.column;
        this.indented = this.indent >= CODE_INDENT;
    }

    // Break out of all containing lists, resetting the tip of the
    // document to the parent of the highest list, and finalizing
    // all the lists.  (This is used to implement the "two blank lines
    // break of of all lists" feature.)
    function breakOutOfLists(block:Node):Void {
        var b = block;
        var last_list = null;
        do {
            if (b.type == List)
                last_list = b;
            b = b.parent;
        } while (b != null);

        if (last_list != null) {
            while (block != last_list) {
                finalize(block, lineNumber);
                block = block.parent;
            }
            finalize(last_list, lineNumber);
            tip = last_list.parent;
        }
    }

    inline function advanceNextNonspace():Void {
        offset = nextNonspace;
        column = nextNonspaceColumn;
    }

    // Finalize and close any unmatched blocks. Returns true.
    function closeUnmatchedBlocks():Void {
        if (allClosed)
            return;
        // finalize any blocks not matched
        while (oldtip != lastMatchedContainer) {
            var parent = oldtip.parent;
            finalize(oldtip, lineNumber - 1);
            oldtip = parent;
        }
        allClosed = true;
    }

    // Add a line to the block at the tip.  We assume the tip
    // can accept lines -- that check should be done before calling this.
    inline function addLine():Void {
        tip.string_content += currentLine.substring(offset) + '\n';
    }

    // Add block of type tag as a child of the tip.  If the tip can't
    // accept children, close and finalize it and try its parent,
    // and so on til we find a block that can accept children.
    function addChild(tag:NodeType, offset:Int):Node {
        while (!blocks[tip.type].canContain(tag))
            finalize(tip, lineNumber - 1);

        var column_number = offset + 1; // offset 0 = column 1
        var newBlock = new Node(tag, [[lineNumber, column_number], [0, 0]]);
        newBlock.string_content = '';
        tip.appendChild(newBlock);
        tip = newBlock;
        return newBlock;
    }

    function advanceOffset(count:Int, columns = false):Void {
        var i = 0;
        var cols = 0;
        var currentLine = this.currentLine;
        while (columns ? (cols < count) : (i < count)) {
            if (currentLine.charAt(this.offset + i) == '\t') {
                cols += (4 - ((this.column + cols) % 4));
            } else {
                cols += 1;
            }
            i++;
        }
        this.offset += i;
        this.column += cols;
    }

    // Parse a list marker and return data on the marker (type,
    // start, delimiter, bullet character, padding) or null.
    static function parseListMarker(ln:String, offset:Int, indent:Int):ListData {
        var rest = ln.substr(offset);
        var spaces_after_marker;
        var match, data;
        if (reBulletListMarker.match(rest)) {
            match = reBulletListMarker.matched(0);
            spaces_after_marker = reBulletListMarker.matched(1).length;
            data = new ListData(Bullet, indent);
        } else if (reOrderedListMarker.match(rest)) {
            match = reOrderedListMarker.matched(0);
            spaces_after_marker = reOrderedListMarker.matched(3).length;
            data = new ListData(Ordered, indent);
            data.start = Std.parseInt(reOrderedListMarker.matched(1));
            data.delimiter = reOrderedListMarker.matched(2);
        } else {
            return null;
        }
        var blank_item = match.length == rest.length;
        if (spaces_after_marker >= 5 || spaces_after_marker < 1 || blank_item)
            data.padding = match.length - spaces_after_marker + 1;
        else
            data.padding = match.length;
        return data;
    }

    // Returns true if the two list items are of the same type,
    // with the same delimiter and bullet character.  This is used
    // in agglomerating list items into lists.
    static inline function listsMatch(list_data:ListData, item_data:ListData):Bool {
        return (list_data.type == item_data.type &&
                list_data.delimiter == item_data.delimiter &&
                list_data.bulletChar == item_data.bulletChar);
    }

    // Returns true if block ends with a blank line, descending if needed
    // into lists and sublists.
    static function endsWithBlankLine(block:Node):Bool {
        while (block != null) {
            if (block.lastLineBlank)
                return true;
            var t = block.type;
            if (t == List || t == Item)
                block = block.lastChild;
            else
                break;
        }
        return false;
    }
}
