import js.Node.process;
import js.node.stream.Readable;

class Test {
    static function main() {
        process.stdin.setEncoding("utf-8");
        process.stdin.on(ReadableEvent.Data, function(inp:String) {
            var p = new Parser();
            var ast = p.parse(inp);
            var ren = new HtmlRenderer();
            var out = ren.render(ast);
            process.stdout.write(out, "utf-8");
        });
    }
}
