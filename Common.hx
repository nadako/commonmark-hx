class Common {
    public static inline var ENTITY = "&(?:#x[a-f0-9]{1,8}|#[0-9]{1,8}|[a-z][a-z0-9]{1,31});";
    public static inline var ESCAPABLE = '[!"#$%&\'()*+,./:;<=>?@[\\\\\\]^_`{|}~-]';

    static inline var TAGNAME = '[A-Za-z][A-Za-z0-9-]*';
    static inline var ATTRIBUTENAME = '[a-zA-Z_:][a-zA-Z0-9:._-]*';
    static inline var UNQUOTEDVALUE = "[^\"'=<>`\\x00-\\x20]+";
    static inline var SINGLEQUOTEDVALUE = "'[^']*'";
    static inline var DOUBLEQUOTEDVALUE = '"[^"]*"';
    static var ATTRIBUTEVALUE = "(?:" + UNQUOTEDVALUE + "|" + SINGLEQUOTEDVALUE + "|" + DOUBLEQUOTEDVALUE + ")";
    static var ATTRIBUTEVALUESPEC = "(?:" + "\\s*=" + "\\s*" + ATTRIBUTEVALUE + ")";
    static var ATTRIBUTE = "(?:" + "\\s+" + ATTRIBUTENAME + ATTRIBUTEVALUESPEC + "?)";
    public static var OPENTAG = "<" + TAGNAME + ATTRIBUTE + "*" + "\\s*/?>";
    public static var CLOSETAG = "</" + TAGNAME + "\\s*[>]";
    static inline var HTMLCOMMENT = "<!---->|<!--(?:-?[^>-])(?:-?[^-])*-->";
    static inline var PROCESSINGINSTRUCTION = "[<][?].*?[?][>]";
    static inline var DECLARATION = "<![A-Z]+" + "\\s+[^>]*>";
    static inline var CDATA = "<!\\[CDATA\\[[\\s\\S]*?\\]\\]>";
    static var HTMLTAG = "(?:" + OPENTAG + "|" + CLOSETAG + "|" + HTMLCOMMENT + "|" + PROCESSINGINSTRUCTION + "|" + DECLARATION + "|" + CDATA + ")";
    public static var reHtmlTag = new EReg('^' + HTMLTAG, 'i');

    static var reBackslashOrAmp = ~/[\\&]/;
    static var reEntityOrEscapedChar = new EReg('\\\\' + ESCAPABLE + '|' + ENTITY, 'gi');

    static var encode:String->String = js.Lib.require("./encode.js");
    static var decode:String->String = js.Lib.require("./decode.js");
    public static var decodeHTML:String->String = js.Lib.require('./entities/decode.js');

    static inline var XMLSPECIAL = '[&<>"]';
    static var reXmlSpecial = new EReg(XMLSPECIAL, 'g');
    static var reXmlSpecialOrEntity = new EReg(ENTITY + '|' + XMLSPECIAL, 'gi');

    static function replaceUnsafeChar(s:String):String {
        switch (s) {
            case '&':
                return '&amp;';
            case '<':
                return '&lt;';
            case '>':
                return '&gt;';
            case '"':
                return '&quot;';
            default:
                return s;
        }
    }

    public static function escapeXml(s:String, preserve_entities:Bool):String {
        if (reXmlSpecial.match(s)) {
            if (preserve_entities)
                return reXmlSpecialOrEntity.map(s, function(r) return replaceUnsafeChar(r.matched(0)));
            else
                return reXmlSpecial.map(s, function(r) return replaceUnsafeChar(r.matched(0)));
        } else {
            return s;
        }
    }

    public static function normalizeURI(uri:String):String {
        return try encode(decode(uri)) catch (_:Dynamic) uri;
    }

    // Replace entities and backslash escapes with literal characters.
    public static function unescapeString(s:String):String {
        if (reBackslashOrAmp.match(s))
            return reEntityOrEscapedChar.map(s, function(r) return unescapeChar(r.matched(0)));
        else
            return s;
    }

    static function unescapeChar(s:String):String {
        if (s.charCodeAt(0) == "\\".code)
            return s.charAt(1);
        else
            return decodeHTML(s);
    }
}
