package commonmark.render;

import commonmark.Common.escapeXml as esc;
import commonmark.Node;

typedef HtmlRendererOptions = {
    @:optional var sourcepos:Bool;
    @:optional var safe:Bool;

    /**
        by default, soft breaks are rendered as newlines in HTML
        set to "<br />" to make them hard breaks
        set to " " if you want to ignore line wrapping in source
    **/
    @:optional var softbreak:String;
}

class HtmlRenderer extends Renderer {
    var options:HtmlRendererOptions;
    var disableTags:Int;

    static var reUnsafeProtocol = ~/^javascript:|vbscript:|file:|data:/i;
    static var reSafeDataProtocol = ~/^data:image\/(?:png|gif|jpeg|webp)/i;

    public function new(?options:HtmlRendererOptions) {
        if (options == null) {
            options = {
                softbreak: "\n",
                sourcepos: false,
                safe: false,
            };
        } else {
            if (options.softbreak == null) options.softbreak = "\n";
            if (options.sourcepos == null) options.sourcepos = false;
            if (options.safe == null) options.safe = false;
        }

        this.options = options;
        this.disableTags = 0;
        this.lastOut = "\n";
    }

    static inline function potentiallyUnsafe(url:String) {
        return reUnsafeProtocol.match(url) && !reSafeDataProtocol.match(url);
    }

    // Helper function to produce an HTML tag.
    function tag(name:String, ?attrs:Array<Array<String>>, ?selfclosing:Bool) {
        if (disableTags > 0)
            return;

        buffer += ('<' + name);

        if (attrs != null && attrs.length > 0) {
            var i = 0;
            var attrib;
            while ((attrib = attrs[i]) != null) {
                buffer += (' ' + attrib[0] + '="' + attrib[1] + '"');
                i++;
            }
        }
        if (selfclosing != null && selfclosing)
            buffer += ' /';
        buffer += '>';
        lastOut = '>';
    }


    /* Node methods */

    override function text(node:Node, _) {
        out(node.literal);
    }

    override function softbreak(_, _) {
        lit(options.softbreak);
    }

    override function linebreak(_, _) {
        tag('br', [], true);
        cr();
    }

    override function link(node:Node, entering:Bool) {
        var attrs = attrs(node);
        if (entering) {
            if (!(options.safe && potentiallyUnsafe(node.destination)))
                attrs.push(['href', esc(node.destination, true)]);
            if (node.title != null && node.title.length > 0)
                attrs.push(['title', esc(node.title, true)]);
            tag('a', attrs);
        } else {
            tag('/a');
        }
    }

    override function image(node:Node, entering:Bool) {
        if (entering) {
            if (disableTags == 0) {
                if (options.safe && potentiallyUnsafe(node.destination))
                    lit('<img src="" alt="');
                else
                    lit('<img src="' + esc(node.destination, true) + '" alt="');
            }
            disableTags++;
        } else {
            disableTags--;
            if (disableTags == 0) {
                if (node.title != null && node.title.length > 0)
                    lit('" title="' + esc(node.title, true));
                lit('" />');
            }
        }
    }

    override function emph(node:Node, entering:Bool) {
        tag(entering ? 'em' : '/em');
    }

    override function strong(node:Node, entering:Bool) {
        tag(entering ? 'strong' : '/strong');
    }

    override function paragraph(node:Node, entering:Bool) {
        var grandparent = node.parent.parent, attrs = attrs(node);
        if (grandparent != null && grandparent.type == List) {
              if (grandparent.listData.tight)
                  return;
        }
        if (entering) {
            cr();
            tag('p', attrs);
        } else {
            tag('/p');
            cr();
        }
    }

    override function heading(node:Node, entering:Bool) {
        var tagname = 'h' + node.level, attrs = attrs(node);
        if (entering) {
            cr();
            tag(tagname, attrs);
        } else {
            tag('/' + tagname);
            cr();
        }
    }

    override function code(node:Node, _) {
        tag('code');
        out(node.literal);
        tag('/code');
    }

    override function code_block(node:Node, _) {
        var info_words = node.info != null ? ~/\s+/.split(node.info) : [];
        var attrs = attrs(node);
        if (info_words.length > 0 && info_words[0].length > 0)
                attrs.push(['class', 'language-' + esc(info_words[0], true)]);
        cr();
        tag('pre');
        tag('code', attrs);
        out(node.literal);
        tag('/code');
        tag('/pre');
        cr();
    }

    override function thematic_break(node:Node, _) {
        var attrs = attrs(node);
        cr();
        tag('hr', attrs, true);
        cr();
    }

    override function block_quote(node:Node, entering:Bool) {
        var attrs = attrs(node);
        if (entering) {
            cr();
            tag('blockquote', attrs);
            cr();
        } else {
            cr();
            tag('/blockquote');
            cr();
        }
    }

    override function list(node:Node, entering:Bool) {
        var tagname = node.listData.type == Bullet ? 'ul' : 'ol', attrs = attrs(node);
        if (entering) {
            var start = node.listData.start;
            if (start != null && start != 1) {
                attrs.push(['start', Std.string(start)]);
            }
            cr();
            tag(tagname, attrs);
            cr();
        } else {
            cr();
            tag('/' + tagname);
            cr();
        }
    }

    override function item(node:Node, entering:Bool) {
        var attrs = attrs(node);
        if (entering) {
            tag('li', attrs);
        } else {
            tag('/li');
            cr();
        }
    }

    override function html_inline(node:Node, _) {
        if (options.safe)
            lit('<!-- raw HTML omitted -->');
        else
            lit(node.literal);
    }

    override function html_block(node:Node, _) {
        cr();
        if (options.safe)
            lit('<!-- raw HTML omitted -->');
        else
            lit(node.literal);
        cr();
    }

    override function custom_inline(node:Node, entering:Bool) {
        if (entering && node.onEnter != null)
            lit(node.onEnter);
        else if (!entering && node.onExit != null)
            lit(node.onExit);
    }

    override function custom_block(node:Node, entering:Bool) {
        cr();
        if (entering && node.onEnter != null)
            this.lit(node.onEnter);
        else if (!entering && node.onExit != null)
            this.lit(node.onExit);
        cr();
    }


    /* Helper methods */

    override function out(s:String) {
        lit(esc(s, false));
    }

    function attrs(node:Node):Array<Array<String>> {
        var att = [];
        if (options.sourcepos) {
            var pos = node.sourcepos;
            if (pos != null)
                att.push(['data-sourcepos', pos.startline + ':' + pos.startcolumn + '-' + pos.endline + ':' + pos.endcolumn]);
        }
        return att;
    }
}
