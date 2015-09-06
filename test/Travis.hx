import sys.FileSystem;

class Travis {
    static function main() {
        var testProgram = switch (Sys.getEnv("TARGET")) {
            case "js":
                makeJS();
            case "neko":
                makeNeko();
            case other:
                throw "Unknown TARGET: " + other;
        };
        Sys.setCwd("CommonMark");
        Sys.command("python3", ["test/spec_tests.py", "--program", testProgram]);
    }

    static function makeJS() {
        Sys.command("haxe", ["build-js.hxml"]);
        return "node " + FileSystem.absolutePath("bin/test.js");
    }

    static function makeNeko() {
        Sys.command("haxe", ["build-neko.hxml"]);
        return "neko " + FileSystem.absolutePath("bin/test.n");
    }
}
