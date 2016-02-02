package commonmark;

import commonmark.Common.escapeXml;

typedef HtmlRendererOptions = {
    var sourcepos:Bool;
    var safe:Bool;
}

class HtmlRenderer {
    var options:HtmlRendererOptions;
    var softbreak:String;

    static var reHtmlTag = ~/<[^>]*>/;
    static var reUnsafeProtocol = ~/^javascript:|vbscript:|file:|data:/i;
    static var reSafeDataProtocol = ~/^data:image\/(?:png|gif|jpeg|webp)/i;

    public function new(?options:HtmlRendererOptions) {
        if (options == null)
            options = {sourcepos: false, safe: false};
        this.options = options;

        softbreak = '\n'; // by default, soft breaks are rendered as newlines in HTML
        // set to "<br />" to make them hard breaks
        // set to " " if you want to ignore line wrapping in source
    }

    static inline function potentiallyUnsafe(url:String) {
        return reUnsafeProtocol.match(url) && !reSafeDataProtocol.match(url);
    }

    public function render(block:Node):String {
        var attrs;
        var info_words;
        var tagname;
        var walker = block.walker();
        var event, node, entering;
        var buffer = "";
        var lastOut = "\n";
        var disableTags = 0;
        var grandparent;
        var out = function(s:String) {
            if (disableTags > 0) {
                buffer += reHtmlTag.replace(s, '');
            } else {
                buffer += s;
            }
            lastOut = s;
        };
        var cr = function() {
            if (lastOut != '\n') {
                buffer += '\n';
                lastOut = '\n';
            }
        };

        var options = this.options;

        while ((event = walker.next()) != null) {
            entering = event.entering;
            node = event.node;

            attrs = [];
            if (options.sourcepos) {
                var pos = node.sourcepos;
                if (pos != null) {
                    attrs.push(['data-sourcepos', Std.string(pos[0][0]) + ':' +
                                Std.string(pos[0][1]) + '-' + Std.string(pos[1][0]) + ':' +
                                Std.string(pos[1][1])]);
                }
            }

            switch (node.type) {
                case Text:
                    out(escapeXml(node.literal, false));

                case Softbreak:
                    out(this.softbreak);

                case Hardbreak:
                    out(tag('br', [], true));
                    cr();

                case Emph:
                    out(tag(entering ? 'em' : '/em'));

                case Strong:
                    out(tag(entering ? 'strong' : '/strong'));

                case HtmlInline:
                    if (options.safe) {
                        out('<!-- raw HTML omitted -->');
                    } else {
                        out(node.literal);
                    }

                case CustomInline:
                    if (entering && node.onEnter != null && node.onEnter.length > 0)
                        out(node.onEnter);
                    else if (!entering && node.onExit != null && node.onExit.length > 0)
                        out(node.onExit);

                case Link:
                    if (entering) {
                        if (!(options.safe && potentiallyUnsafe(node.destination))) {
                            attrs.push(['href', escapeXml(node.destination, true)]);
                        }
                        if (node.title != null && node.title.length > 0)
                            attrs.push(['title', escapeXml(node.title, true)]);
                        out(tag('a', attrs));
                    } else {
                        out(tag('/a'));
                    }

                case Image:
                    if (entering) {
                        if (disableTags == 0) {
                            if (options.safe &&
                                 potentiallyUnsafe(node.destination)) {
                                out('<img src="" alt="');
                            } else {
                                out('<img src="' + escapeXml(node.destination, true) +
                                    '" alt="');
                            }
                        }
                        disableTags += 1;
                    } else {
                        disableTags -= 1;
                        if (disableTags == 0) {
                            if (node.title != null && node.title.length > 0)
                                out('" title="' + escapeXml(node.title, true));
                            out('" />');
                        }
                    }

                case Code:
                    out(tag('code') + escapeXml(node.literal, false) + tag('/code'));

                case Document:

                case Paragraph:
                    grandparent = node.parent.parent;
                    var done = false;
                    if (grandparent != null &&
                        grandparent.type == List) {
                        if (grandparent.listTight) {
                            done = true;
                        }
                    }
                    if (!done) {
                        if (entering) {
                            cr();
                            out(tag('p', attrs));
                        } else {
                            out(tag('/p'));
                            cr();
                        }
                    }

                case BlockQuote:
                    if (entering) {
                        cr();
                        out(tag('blockquote', attrs));
                        cr();
                    } else {
                        cr();
                        out(tag('/blockquote'));
                        cr();
                    }

                case Item:
                    if (entering) {
                        out(tag('li', attrs));
                    } else {
                        out(tag('/li'));
                        cr();
                    }

                case List:
                    tagname = node.listType == Bullet ? 'ul' : 'ol';
                    if (entering) {
                        var start = node.listStart;
                        if (start != null && start != 1) {
                            attrs.push(['start', Std.string(start)]);
                        }
                        cr();
                        out(tag(tagname, attrs));
                        cr();
                    } else {
                        cr();
                        out(tag('/' + tagname));
                        cr();
                    }

                case Heading:
                    tagname = 'h' + node.level;
                    if (entering) {
                        cr();
                        out(tag(tagname, attrs));
                    } else {
                        out(tag('/' + tagname));
                        cr();
                    }

                case CodeBlock:
                    info_words = node.info != null ? ~/\s+/g.split(node.info) : [];
                    if (info_words.length > 0 && info_words[0].length > 0) {
                        attrs.push(['class', 'language-' + escapeXml(info_words[0], true)]);
                    }
                    cr();
                    out(tag('pre') + tag('code', attrs));
                    out(escapeXml(node.literal, false));
                    out(tag('/code') + tag('/pre'));
                    cr();

                case HtmlBlock:
                    cr();
                    if (options.safe) {
                        out('<!-- raw HTML omitted -->');
                    } else {
                        out(node.literal);
                    }
                    cr();

                case CustomBlock:
                    cr();
                    if (entering && node.onEnter != null && node.onEnter.length > 0)
                       out(node.onEnter);
                    else if (!entering && node.onExit != null && node.onExit.length > 0)
                       out(node.onExit);
                    cr();

                case ThematicBreak:
                    cr();
                    out(tag('hr', attrs, true));
                    cr();
            }

        }
        return buffer;
    }

    // Helper function to produce an HTML tag.
    static function tag(name:String, ?attrs:Array<Array<String>>, ?selfclosing:Bool) {
        var result = '<' + name;
        if (attrs != null && attrs.length > 0) {
            var i = 0;
            var attrib;
            while ((attrib = attrs[i]) != null) {
                result += ' ' + attrib[0] + '="' + attrib[1] + '"';
                i++;
            }
        }
        if (selfclosing)
            result += ' /';

        result += '>';
        return result;
    }
}
