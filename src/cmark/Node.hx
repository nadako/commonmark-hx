package cmark;

@:enum abstract NodeType(Int) to Int {
    var Document       = 1;
    var List           = 2;
    var Item           = 3;
    var BlockQuote     = 4;
    var Heading        = 5;
    var ThematicBreak  = 6;
    var CodeBlock      = 7;
    var HtmlBlock      = 8;
    var Paragraph      = 9;
    var Text           = 10;
    var Hardbreak      = 11;
    var Softbreak      = 12;
    var Code           = 13;
    var Link           = 14;
    var Image          = 15;
    var Emph           = 16;
    var Strong         = 17;
    var HtmlInline     = 18;
    var CustomInline   = 19;
    var CustomBlock    = 20;
}

@:enum abstract ListType(Int) to Int {
    var Ordered = 1;
    var Bullet  = 2;
}

typedef SourcePos = Array<Array<Int>>;

@:publicFields
class ListData {
    var type:ListType;
    var tight:Bool;
    var start:Null<Int>;
    var delimiter:String;
    var bulletChar:String;
    var markerOffset:Int;
    var padding:Int;
    function new(type, indent) {
        this.type = type;
        this.markerOffset = indent;
        this.padding = 0;
        this.tight = true; // lists are tight by default
    }
}

class Node {
    public var isContainer(get,never):Bool;
    public var type(default,null):NodeType;
    public var firstChild(default,null):Node;
    public var lastChild(default,null):Node;
    public var next(default,null):Node;
    public var prev(default,null):Node;
    public var parent(default,null):Node;
    public var sourcepos(default,null):SourcePos;
    public var literal:String;
    public var destination:String;
    public var title:String;
    public var info:String;
    public var level:Int;
    public var listType(get,set):ListType;
    public var listTight(get,set):Bool;
    public var listStart(get,set):Null<Int>;
    public var listDelimiter(get,set):String;
    public var htmlBlockType:Int;

    public var listData:ListData;
    public var lastLineBlank:Bool;
    public var open:Bool;

    public var string_content:String;
    public var isFenced:Bool;
    public var fenceChar:String;
    public var fenceLength:Int;
    public var fenceOffset:Int;
    public var onEnter:String;
    public var onExit:String;

    public function new(nodeType:NodeType, ?sourcepos:SourcePos) {
        this.type = nodeType;
        this.sourcepos = sourcepos;
        listData = new ListData(Bullet, 0);
        lastLineBlank = false;
        open = true;
        isFenced = false;
        fenceLength = 0;
    }

    inline function get_listType() return listData.type;
    inline function set_listType(t) return listData.type = t;

    inline function get_listTight() return listData.tight;
    inline function set_listTight(t) return listData.tight = t;

    inline function get_listStart() return listData.start;
    inline function set_listStart(n) return listData.start = n;

    inline function get_listDelimiter() return listData.delimiter;
    inline function set_listDelimiter(delim) return listData.delimiter = delim;

    function get_isContainer():Bool {
        switch (type) {
            case Document
               | BlockQuote
               | List
               | Item
               | Paragraph
               | Heading
               | Emph
               | Strong
               | Link
               | Image
               :
                return true;
            default:
                return false;
        }
    }

    public function appendChild(child:Node):Void {
        child.unlink();
        child.parent = this;
        if (this.lastChild != null) {
            this.lastChild.next = child;
            child.prev = this.lastChild;
            this.lastChild = child;
        } else {
            this.firstChild = child;
            this.lastChild = child;
        }
    }

    function prependChild(child:Node):Void {
        child.unlink();
        child.parent = this;
        if (this.firstChild != null) {
            this.firstChild.prev = child;
            child.next = this.firstChild;
            this.firstChild = child;
        } else {
            this.firstChild = child;
            this.lastChild = child;
        }
    }

    public function unlink() {
        if (this.prev != null)
            this.prev.next = this.next;
        else if (this.parent != null)
            this.parent.firstChild = this.next;

        if (this.next != null)
            this.next.prev = this.prev;
        else if (this.parent != null)
            this.parent.lastChild = this.prev;

        this.parent = null;
        this.next = null;
        this.prev = null;
    }

    public function insertAfter(sibling:Node):Void {
        sibling.unlink();
        sibling.next = this.next;
        if (sibling.next != null)
            sibling.next.prev = sibling;

        sibling.prev = this;
        this.next = sibling;
        sibling.parent = this.parent;

        if (sibling.next == null)
            sibling.parent.lastChild = sibling;
    }

    function insertBefore(sibling:Node):Void {
        sibling.unlink();
        sibling.prev = this.prev;
        if (sibling.prev != null)
            sibling.prev.next = sibling;
        sibling.next = this;
        this.prev = sibling;
        sibling.parent = this.parent;
        if (sibling.prev == null)
            sibling.parent.firstChild = sibling;
    }

    public inline function walker() return new NodeWalker(this);
}

typedef NodeWalkerData = {
    var node:Node;
    var entering:Bool;
}

class NodeWalker {
    var current:Node;
    var root:Node;
    var entering:Bool;

    public function new(root) {
        this.current = root;
        this.root = root;
        this.entering = true;
    }

    public function next():NodeWalkerData {
        var cur = this.current;
        var entering = this.entering;

        if (cur == null)
            return null;

        var container = cur.isContainer;

        if (entering && container) {
            if (cur.firstChild != null) {
                this.current = cur.firstChild;
                this.entering = true;
            } else {
                // stay on node but exit
                this.entering = false;
            }
        } else if (cur == this.root) {
            this.current = null;
        } else if (cur.next == null) {
            this.current = cur.parent;
            this.entering = false;
        } else {
            this.current = cur.next;
            this.entering = true;
        }

        return {entering: entering, node: cur};
    }

    function resumeAt(node:Node, entering:Bool):Void {
        this.current = node;
        this.entering = entering;
    }
}
