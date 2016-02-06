[![Build Status](https://travis-ci.org/nadako/commonmark-hx.svg?branch=master)](https://travis-ci.org/nadako/commonmark-hx)

# CommonMark for Haxe

This is a port the [JavaScript reference implementation](https://github.com/jgm/commonmark.js) of the [CommonMark](http://commonmark.org/) spec.

* Current spec version version: 0.24
* Corresponding JS implementation commit: https://github.com/jgm/commonmark.js/commit/b46bfd7a9a42015968e231cb16a4a634bd6e85be


## Example usage

This is similar to the original JS version

```haxe
var parser = new commonmark.Parser();
var ast = parser.parse("# Hello");
var writer = new commonmark.HtmlRenderer();
var html = writer.render(ast);
```
