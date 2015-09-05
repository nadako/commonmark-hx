class Main {
    static function main() {
        var inp = "<foo+special@Bar.baz-bar0.com>";
        var p = new Parser();
        var ast = p.parse(inp);
        var ren = new HtmlRenderer();
        var out = ren.render(ast);
        trace(out);
    }
}
