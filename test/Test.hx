class Test {
    static function main() {
        var proc = (untyped process);
        proc.stdin.setEncoding("utf-8");
        proc.stdin.on("data", function(inp:String) {
            var p = new Parser();
            var ast = p.parse(inp);
            var ren = new HtmlRenderer();
            var out = ren.render(ast);
            proc.stdout.write(out, "utf-8");
        });
    }
}
