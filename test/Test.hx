class Test {
    static function main() {
        #if js
        var proc = (untyped process);
        proc.stdin.setEncoding("utf-8");
        proc.stdin.on("data", function(inp:String) {
            var out = run(inp);
            proc.stdout.write(out, "utf-8");
        });
        #elseif sys
        var inp = Sys.stdin().readAll().toString();
        var out = run(inp);
        Sys.stdout().writeString(out);
        Sys.stdout().flush();
        #else
        #error not implemented
        #end
    }

    static function run(inp:String):String {
        var p = new commonmark.Parser();
        var ast = p.parse(inp);
        var ren = new commonmark.HtmlRenderer();
        return ren.render(ast);
    }
}
