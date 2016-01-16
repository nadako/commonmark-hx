[![Build Status](https://travis-ci.org/nadako/commonmark-hx.svg?branch=master)](https://travis-ci.org/nadako/commonmark-hx)

# CommonMark for Haxe

This is a port the [JavaScript reference implementation](https://github.com/jgm/commonmark.js) of the [CommonMark](http://commonmark.org/) spec.

* Current spec version version: 0.24
* Corresponding JS implementation commit: https://github.com/jgm/commonmark.js/commit/d0bf5713bd3ff1a618fd855fbe50127140a0fbe4


## Example usage

This is similar to the original JS version

```haxe
var parser = new cmark.Parser();
var ast = parser.parse("# Hello");
var writer = new cmark.HtmlRenderer();
var html = writer.render(ast);
```
