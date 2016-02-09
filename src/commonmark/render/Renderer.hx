package commonmark.render;

import commonmark.Node;

class Renderer {
    var buffer:String;
    var lastOut:String;

    /**
     *  Walks the AST and calls member methods for each Node type.
     *
     *  @param ast {Node} The root of the abstract syntax tree.
     */
    public function render(ast:Node):String {
        buffer = '';
        lastOut = '\n';
        var walker = ast.walker();
        var event;
        while ((event = walker.next()) != null) {
            switch (event.node.type) {
                case CustomBlock: custom_block(event.node, event.entering);
                case CustomInline: custom_inline(event.node, event.entering);
                case HtmlInline: html_inline(event.node, event.entering);
                case Strong: strong(event.node, event.entering);
                case Emph: emph(event.node, event.entering);
                case Image: image(event.node, event.entering);
                case Link: link(event.node, event.entering);
                case Code: code(event.node, event.entering);
                case Softbreak: softbreak(event.node, event.entering);
                case Linebreak: linebreak(event.node, event.entering);
                case Text: text(event.node, event.entering);
                case Paragraph: paragraph(event.node, event.entering);
                case HtmlBlock: html_block(event.node, event.entering);
                case CodeBlock: code_block(event.node, event.entering);
                case ThematicBreak: thematic_break(event.node, event.entering);
                case Heading: heading(event.node, event.entering);
                case BlockQuote: block_quote(event.node, event.entering);
                case Item: item(event.node, event.entering);
                case List: list(event.node, event.entering);
                case Document: document(event.node, event.entering);
            }
        }
        return buffer;
    }

    function custom_block(node:Node, entering:Bool):Void {}
    function custom_inline(node:Node, entering:Bool):Void {}
    function html_inline(node:Node, entering:Bool):Void {}
    function strong(node:Node, entering:Bool):Void {}
    function emph(node:Node, entering:Bool):Void {}
    function image(node:Node, entering:Bool):Void {}
    function link(node:Node, entering:Bool):Void {}
    function code(node:Node, entering:Bool):Void {}
    function softbreak(node:Node, entering:Bool):Void {}
    function linebreak(node:Node, entering:Bool):Void {}
    function text(node:Node, entering:Bool):Void {}
    function paragraph(node:Node, entering:Bool):Void {}
    function html_block(node:Node, entering:Bool):Void {}
    function code_block(node:Node, entering:Bool):Void {}
    function thematic_break(node:Node, entering:Bool):Void {}
    function heading(node:Node, entering:Bool):Void {}
    function block_quote(node:Node, entering:Bool):Void {}
    function item(node:Node, entering:Bool):Void {}
    function list(node:Node, entering:Bool):Void {}
    function document(node:Node, entering:Bool):Void {}

    /**
     *  Concatenate a literal string to the buffer.
     *
     *  @param str {String} The string to concatenate.
     */
    function lit(str:String):Void {
        buffer += str;
        lastOut = str;
    }

    function cr() {
        if (lastOut != '\n')
            lit('\n');
    }

    /**
     *  Concatenate a string to the buffer possibly escaping the content.
     *
     *  Concrete renderer implementations should override this method.
     *
     *  @param str {String} The string to concatenate.
     */
    function out(str:String):Void {
        lit(str);
    }
}
