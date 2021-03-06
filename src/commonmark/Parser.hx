package commonmark;

import commonmark.Common.unescapeString;
import commonmark.Common.OPENTAG;
import commonmark.Common.CLOSETAG;
import commonmark.Node.ListData;
import commonmark.Node.NodeType;
import commonmark.Node.SourcePos;

typedef ParserOptions = {
    >InlineParser.InlineParserOptions,
}

interface IBlockBehaviour {
    /**
        run to check whether the block is continuing
        at a certain line and offset (e.g. whether a block quote contains a `>`)
    **/
    function tryContinue(parser:Parser, block:Node):TryContinueResult;

    /**
        run when the block is closed
    **/
    function finalize(parser:Parser, block:Node):Void;
    function canContain(t:NodeType):Bool;
    function acceptsLines():Bool;
}

@:enum abstract TryStartResult(Int) {
    /**
        no match
    **/

    var BSNoMatch = 0;
    /**
        matched container, keep going
    **/
    var BSContainer = 1;

    /**
        matched leaf, no more block starts
    **/
    var BSLeaf = 2;
}

@:enum abstract TryContinueResult(Int) {
    /**
        matched
    **/
    var CMatched = 0;

    /**
        not matched
    **/
    var CNotMatched = 1;

    /**
        we've dealt with this line completely, go to next
    **/
    var CDone = 2;
}

@:publicFields
class DocumentBehaviour implements IBlockBehaviour {
    function new() {}
    function tryContinue(_, _) return CMatched;
    function finalize(_, _) {};
    function canContain(t:NodeType) return (t != Item);
    function acceptsLines() return false;
}

@:publicFields
@:access(commonmark.Parser)
class ListBehaviour implements IBlockBehaviour {
    function new() {}
    function tryContinue(_, _) return CMatched;
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
@:access(commonmark.Parser)
class BlockQuoteBehaviour implements IBlockBehaviour {
    function new() {}
    function tryContinue(parser:Parser, _) {
        var ln = parser.currentLine;
        if (!parser.indented && Parser.peek(ln, parser.nextNonspace) == ">".code) {
            parser.advanceNextNonspace();
            parser.advanceOffset(1, false);
            if (Parser.isSpaceOrTab(Parser.peek(ln, parser.offset)))
                parser.advanceOffset(1, true);
        } else {
            return CNotMatched;
        }
        return CMatched;
    }
    function finalize(_, _) {};
    function canContain(t:NodeType) return (t != Item);
    function acceptsLines() return false;

    static function tryStart(parser:Parser, block:Node):TryStartResult {
        if (!parser.indented && Parser.peek(parser.currentLine, parser.nextNonspace) == ">".code) {
            parser.advanceNextNonspace();
            parser.advanceOffset(1, false);
            // optional following space
            if (Parser.isSpaceOrTab(Parser.peek(parser.currentLine, parser.offset)))
                parser.advanceOffset(1, true);
            parser.closeUnmatchedBlocks();
            parser.addChild(BlockQuote, parser.nextNonspace);
            return BSContainer;
        } else {
            return BSNoMatch;
        }
    }
}

@:publicFields
@:access(commonmark.Parser)
class ItemBehaviour implements IBlockBehaviour {
    static var reBulletListMarker = ~/^[*+-]/;
    static var reOrderedListMarker = ~/^(\d{1,9})([.)])/;

    function new() {}
    function tryContinue(parser:Parser, container:Node) {
        if (parser.blank) {
            if (container.firstChild == null)
                return CNotMatched; // Blank line after empty list item
            else
                parser.advanceNextNonspace();
        } else if (parser.indent >= container.listData.markerOffset + container.listData.padding) {
            parser.advanceOffset(container.listData.markerOffset + container.listData.padding, true);
        } else {
            return CNotMatched;
        }
        return CMatched;
    }
    function finalize(_, _) {}
    function canContain(t:NodeType) return (t != Item);
    function acceptsLines() return false;
    static function tryStart(parser:Parser, container:Node):TryStartResult {
        var data;
        if ((!parser.indented || container.type == List) && (data = parseListMarker(parser, container)) != null) {
            parser.closeUnmatchedBlocks();

            // add the list if needed
            if (parser.tip.type != List || !(listsMatch(container.listData, data))) {
                container = parser.addChild(List, parser.nextNonspace);
                container.listData = data;
            }

            // add the list item
            container = parser.addChild(Item, parser.nextNonspace);
            container.listData = data;
            return BSContainer;
        } else {
            return BSNoMatch;
        }
    }

    // Parse a list marker and return data on the marker (type,
    // start, delimiter, bullet character, padding) or null.
    static function parseListMarker(parser:Parser, container:Node):ListData {
        var rest = parser.currentLine.substr(parser.nextNonspace);
        var data, match;
        if (reBulletListMarker.match(rest)) {
            data = new ListData(Bullet, parser.indent);
            data.bulletChar = reBulletListMarker.matched(0).charAt(0);
            match = reBulletListMarker.matched(0);
        } else if (reOrderedListMarker.match(rest) && (container.type != Paragraph || reOrderedListMarker.matched(1) == "1")) {
            data = new ListData(Ordered, parser.indent);
            data.start = Std.parseInt(reOrderedListMarker.matched(1));
            data.delimiter = reOrderedListMarker.matched(2);
            match = reOrderedListMarker.matched(0);
        } else {
            return null;
        }
        // make sure we have spaces after
        var nextc = Parser.peek(parser.currentLine, parser.nextNonspace + match.length);
        if (!(nextc == -1 || nextc == "\t".code || nextc == " ".code)) {
            return null;
        }

        // if it interrupts paragraph, make sure first line isn't blank
        if (container.type == Paragraph && !Parser.reNonSpace.match(parser.currentLine.substring(parser.nextNonspace + match.length)))
            return null;

        // we've got a match! advance offset and calculate padding
        parser.advanceNextNonspace(); // to start of marker
        parser.advanceOffset(match.length, true); // to end of marker
        var spacesStartCol = parser.column;
        var spacesStartOffset = parser.offset;
        do {
            parser.advanceOffset(1, true);
            nextc = Parser.peek(parser.currentLine, parser.offset);
        } while (parser.column - spacesStartCol < 5 && Parser.isSpaceOrTab(nextc));
        var blank_item = Parser.peek(parser.currentLine, parser.offset) == -1;
        var spaces_after_marker = parser.column - spacesStartCol;
        if (spaces_after_marker >= 5 || spaces_after_marker < 1 || blank_item) {
            data.padding = match.length + 1;
            parser.column = spacesStartCol;
            parser.offset = spacesStartOffset;
            if (Parser.isSpaceOrTab(Parser.peek(parser.currentLine, parser.offset))) {
                parser.advanceOffset(1, true);
            }
        } else {
            data.padding = match.length + spaces_after_marker;
        }
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
}

@:publicFields
@:access(commonmark.Parser)
class HeadingBehaviour implements IBlockBehaviour {
    static var reATXHeadingMarker = ~/^#{1,6}(?:[ \t]+|$)/;
    static var reSetextHeadingLine = ~/^(?:=+|-+) *$/;

    function new() {}
    function tryContinue(_, _) {
        // a heading can never container > 1 line, so fail to match:
        return CNotMatched;
    }
    function finalize(_, _) {};
    function canContain(_) return false;
    function acceptsLines() return false;

    static function tryStartATX(parser:Parser, container:Node):TryStartResult {
        if (!parser.indented && (reATXHeadingMarker.match(parser.currentLine.substring(parser.nextNonspace)))) {
            parser.advanceNextNonspace();
            parser.advanceOffset(reATXHeadingMarker.matched(0).length, false);
            parser.closeUnmatchedBlocks();
            var container = parser.addChild(Heading, parser.nextNonspace);
            container.level = StringTools.trim(reATXHeadingMarker.matched(0)).length; // number of #s
            // remove trailing ###s:
            container.string_content = ~/ +#+ *$/.replace(~/^ *#+ *$/.replace(parser.currentLine.substr(parser.offset), ''), '');
            parser.advanceOffset(parser.currentLine.length - parser.offset);
            return BSLeaf;
        } else {
            return BSNoMatch;
        }
    }

    static function tryStartSetext(parser:Parser, container:Node):TryStartResult {
        if (!parser.indented && container.type == Paragraph && reSetextHeadingLine.match(parser.currentLine.substring(parser.nextNonspace))) {
            parser.closeUnmatchedBlocks();
            var heading = new Node(Heading, container.sourcepos);
            heading.level = reSetextHeadingLine.matched(0).charAt(0) == '=' ? 1 : 2;
            heading.string_content = container.string_content;
            container.insertAfter(heading);
            container.unlink();
            parser.tip = heading;
            parser.advanceOffset(parser.currentLine.length - parser.offset, false);
            return BSLeaf;
        } else {
            return BSNoMatch;
        }
    }
}

@:publicFields
@:access(commonmark.Parser)
class ThematicBreakBehaviour implements IBlockBehaviour {
    static var reThematicBreak = ~/^(?:(?:\*[ \t]*){3,}|(?:_[ \t]*){3,}|(?:-[ \t]*){3,})[ \t]*$/;

    function new() {}
    function tryContinue(_, _) {
        // a thematic break can never container > 1 line, so fail to match:
        return CNotMatched;
    };
    function finalize(_, _) {};
    function canContain(_) return false;
    function acceptsLines() return false;
    static function tryStart(parser:Parser, container:Node):TryStartResult {
        if (!parser.indented && reThematicBreak.match(parser.currentLine.substr(parser.nextNonspace))) {
            parser.closeUnmatchedBlocks();
            parser.addChild(ThematicBreak, parser.nextNonspace);
            parser.advanceOffset(parser.currentLine.length - parser.offset, false);
            return BSLeaf;
        } else {
            return BSNoMatch;
        }
    }
}

@:publicFields
@:access(commonmark.Parser)
class CodeBlockBehaviour implements IBlockBehaviour {
    static var reCodeFence = ~/^`{3,}(?!.*`)|^~{3,}(?!.*~)/;
    static var reClosingCodeFence = ~/^(?:`{3,}|~{3,})(?= *$)/;

    function new() {}
    function tryContinue(parser:Parser, container:Node) {
        var ln = parser.currentLine;
        var indent = parser.indent;
        if (container.isFenced) { // fenced
            var match = indent <= 3 && ln.charAt(parser.nextNonspace) == container.fenceChar && reClosingCodeFence.match(ln.substr(parser.nextNonspace));
            if (match && reClosingCodeFence.matched(0).length >= container.fenceLength) {
                // closing fence - we're at end of line, so we can return
                parser.finalize(container, parser.lineNumber);
                return CDone;
            } else {
                // skip optional spaces of fence offset
                var i = container.fenceOffset;
                while (i > 0 && Parser.isSpaceOrTab(Parser.peek(ln, parser.offset))) {
                    parser.advanceOffset(1, true);
                    i--;
                }
            }
        } else { // indented
            if (indent >= Parser.CODE_INDENT) {
                parser.advanceOffset(Parser.CODE_INDENT, true);
            } else if (parser.blank) {
                parser.advanceNextNonspace();
            } else {
                return CNotMatched;
            }
        }
        return CMatched;
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

    static function tryStartFenced(parser:Parser, container:Node):TryStartResult {
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
            return BSLeaf;
        } else {
            return BSNoMatch;
        }
    }

    static function tryStartIndented(parser:Parser, container:Node):TryStartResult {
        if (parser.indented && parser.tip.type != Paragraph && !parser.blank) {
            // indented code
            parser.advanceOffset(Parser.CODE_INDENT, true);
            parser.closeUnmatchedBlocks();
            parser.addChild(CodeBlock, parser.offset);
            return BSLeaf;
        } else {
            return BSNoMatch;
        }
    }
}

@:publicFields
@:access(commonmark.Parser)
class HtmlBlockBehaviour implements IBlockBehaviour {
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

    function new() {}
    function tryContinue(parser:Parser, container:Node) {
        return ((parser.blank && (container.htmlBlockType == 6 || container.htmlBlockType == 7)) ? CNotMatched : CMatched);
    }
    function finalize(parser:Parser, block:Node) {
        block.literal = ~/(\n *)+$/.replace(block.string_content, '');
        block.string_content = null; // allow GC
    }
    function canContain(_) return false;
    function acceptsLines() return true;
    static function tryStart(parser:Parser, container:Node):TryStartResult {
        if (!parser.indented && Parser.peek(parser.currentLine, parser.nextNonspace) == "<".code) {
            var s = parser.currentLine.substr(parser.nextNonspace);
            for (blockType in 1...8) {
                if (reHtmlBlockOpen[blockType].match(s) && (blockType < 7 || container.type != Paragraph)) {
                    parser.closeUnmatchedBlocks();
                    // We don't adjust parser.offset;
                    // spaces are part of the HTML block:
                    var b = parser.addChild(HtmlBlock, parser.offset);
                    b.htmlBlockType = blockType;
                    return BSLeaf;
                }
            }
        }
        return BSNoMatch;
    }
}

@:publicFields
@:access(commonmark.Parser)
class ParagraphBehaviour implements IBlockBehaviour {
    function new() {}
    function tryContinue(parser:Parser, _) {
        return (parser.blank ? CNotMatched : CMatched);
    }
    function finalize(parser:Parser, block:Node) {
        var pos;
        var hasReferenceDefs = false;

        // try parsing the beginning as link reference definitions:
        while (Parser.peek(block.string_content, 0) == "[".code && (pos = parser.inlineParser.parseReference(block.string_content, parser.refmap)) != 0) {
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
    var indented(get,never):Bool;
    var blank:Bool;
    var partiallyConsumedTab:Bool;
    var allClosed:Bool;
    var lastMatchedContainer:Node;
    var lastLineLength:Int;
    var refmap:Map<String,InlineParser.Ref>;
    var options:ParserOptions;

    static inline var CODE_INDENT = 4;

    static var reLineEnding = ~/\r\n|\n|\r/g;
    static var reMaybeSpecial = ~/^[#`~*+_=<>0-9-]/;
    static var reHtmlBlockClose = [
        ~/./, // dummy for 0
        ~/<\/(?:script|pre|style)>/i,
        ~/-->/,
        ~/\?>/,
        ~/>/,
        ~/\]\]>/
    ];
    static var reNonSpace = ~/[^ \t\r\n]/;

    static inline function isSpaceOrTab(c:Int):Bool {
        return c == " ".code || c == "\t".code;
    }

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

    var blocks:Map<NodeType,IBlockBehaviour> = [
        Document => new DocumentBehaviour(),
        List => new ListBehaviour(),
        BlockQuote => new BlockQuoteBehaviour(),
        Item => new ItemBehaviour(),
        Heading => new HeadingBehaviour(),
        ThematicBreak => new ThematicBreakBehaviour(),
        CodeBlock => new CodeBlockBehaviour(),
        HtmlBlock => new HtmlBlockBehaviour(),
        Paragraph => new ParagraphBehaviour(),
    ];

    static var blockStarts = [
        BlockQuoteBehaviour.tryStart,
        HeadingBehaviour.tryStartATX,
        CodeBlockBehaviour.tryStartFenced,
        HtmlBlockBehaviour.tryStart,
        HeadingBehaviour.tryStartSetext,
        ThematicBreakBehaviour.tryStart,
        ItemBehaviour.tryStart,
        CodeBlockBehaviour.tryStartIndented,
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
        blank = false;
        partiallyConsumedTab = false;
        allClosed = true;
        lastMatchedContainer = doc;
        refmap = new Map();
        lastLineLength = 0;
    }

    inline function newDocument() return new Node(Document, new SourcePos(1, 1, 0, 0));

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
        if (input.charCodeAt(input.length - 1) == "\n".code)
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
        column = 0;
        blank = false;
        partiallyConsumedTab = false;
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

            switch (blocks[container.type].tryContinue(this, container)) {
                case CMatched: // we've matched, keep going
                case CNotMatched: // we've failed to match a block
                    all_matched = false;
                case CDone: // we've hit end of line for fenced code close and can return
                    lastLineLength = ln.length;
                    return;
            }
            if (!all_matched) {
                container = container.parent; // back up to last matching block
                break;
            }
        }

        allClosed = (container == oldtip);
        lastMatchedContainer = container;

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
                if (res == BSContainer) {
                    container = tip;
                    break;
                } else if (res == BSLeaf) {
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
            var lastLineBlank = blank && !(t == BlockQuote || (t == CodeBlock && container.isFenced) || (t == Item && container.firstChild == null && container.sourcepos.startline == this.lineNumber));

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
        block.sourcepos.endline = lineNumber;
        block.sourcepos.endcolumn = lastLineLength;
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
            if (!event.entering && (t == Paragraph || t == Heading))
                inlineParser.parse(node);
        }
    }

    function findNextNonspace():Void {
        var i = offset;
        var cols = column;
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
        blank = (c == '\n' || c == '\r' || c == '');
        nextNonspace = i;
        nextNonspaceColumn = cols;
        indent = nextNonspaceColumn - column;
    }

    inline function get_indented() return indent >= CODE_INDENT;

    inline function advanceNextNonspace():Void {
        offset = nextNonspace;
        column = nextNonspaceColumn;
        partiallyConsumedTab = false;
    }

    // Finalize and close any unmatched blocks.
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
        if (partiallyConsumedTab) {
            offset++; // skip over tab
            // add space characters:
            var charsToTab = 4 - (this.column % 4);
            for (_ in 0...charsToTab)
                tip.string_content += " ";
        }
        tip.string_content += currentLine.substring(offset) + '\n';
    }

    // Add block of type tag as a child of the tip.  If the tip can't
    // accept children, close and finalize it and try its parent,
    // and so on til we find a block that can accept children.
    function addChild(tag:NodeType, offset:Int):Node {
        while (!blocks[tip.type].canContain(tag))
            finalize(tip, lineNumber - 1);

        var column_number = offset + 1; // offset 0 = column 1
        var newBlock = new Node(tag, new SourcePos(lineNumber, column_number, 0, 0));
        newBlock.string_content = '';
        tip.appendChild(newBlock);
        tip = newBlock;
        return newBlock;
    }

    function advanceOffset(count:Int, columns = false):Void {
        var currentLine = this.currentLine;
        var c;
        while (count > 0 && (c = currentLine.charAt(offset)) != null) {
            if (c == "\t") {
                var charsToTab = 4 - (column % 4);
                if (columns) {
                    partiallyConsumedTab = charsToTab > count;
                    var charsToAdvance = charsToTab > count ? count : charsToTab;
                    column += charsToAdvance;
                    offset += partiallyConsumedTab ? 0 : 1;
                    count -= charsToAdvance;
                } else {
                    partiallyConsumedTab = false;
                    column += charsToTab;
                    offset += 1;
                    count -= 1;
                }
            } else {
                partiallyConsumedTab = false;
                offset += 1;
                column += 1; // assume ascii; block starts are ascii
                count -= 1;
            }
        }
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
