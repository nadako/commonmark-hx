import sys.FileSystem;

class Travis {
    static function main() {
        var testProgram = switch (Sys.getEnv("TARGET")) {
            case "js":
                makeJS();
            case "neko":
                makeNeko();
            case "cs":
                makeCS();
            case other:
                throw "Unknown TARGET: " + other;
        };
        Sys.setCwd("CommonMark");
        var exitCode = Sys.command("python3", ["test/spec_tests.py", "--program", testProgram]);
        Sys.exit(exitCode);
    }

    static function makeJS() {
        Sys.command("haxe", ["build-js.hxml"]);
        return "node " + FileSystem.absolutePath("bin/test.js");
    }

    static function makeNeko() {
        Sys.command("haxe", ["build-neko.hxml"]);
        return "neko " + FileSystem.absolutePath("bin/test.n");
    }

    static function makeCS() {
        Sys.command("haxe", ["build-cs.hxml"]);
        return "mono " + FileSystem.absolutePath("bin/cs/bin/Test.exe");
    }
}
