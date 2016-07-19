[![Build Status](https://travis-ci.org/nadako/commonmark-hx.svg?branch=master)](https://travis-ci.org/nadako/commonmark-hx)

# CommonMark for Haxe

This is a port the [JavaScript reference implementation](https://github.com/jgm/commonmark.js) of the [CommonMark](http://commonmark.org/) spec.

* Current spec version version: 0.26
* Corresponding JS implementation commit: https://github.com/jgm/commonmark.js/commit/2a569ad9b4bb839e88bae03b4c1e5de176bcf357

It's currently only passes CommonMark spec tests on *JavaScript* and *C#* targets.

## Example usage

This is similar to the original JS version

```haxe
var parser = new commonmark.Parser();
var ast = parser.parse("# Hello");
var writer = new commonmark.HtmlRenderer();
var html = writer.render(ast);
```
