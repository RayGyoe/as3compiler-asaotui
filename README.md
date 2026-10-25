# asaot.ui — online demo (generated)

This branch is a build output, not a source tree. Do not edit it by hand.

It is the `web` arm of `ui-demo/` in [RayGyoe/as3compiler-asaotui](https://github.com/RayGyoe/as3compiler-asaotui):
the same 43-page component documentation site that the desktop arms show,
compiled by `as-aot` to WASI and linked by emcc into a single page.

Source, and the command that produces these files:

```
git clone https://github.com/RayGyoe/as3compiler-asaotui.git
cd as3compiler-asaotui/ui-demo/air-gallery && ./build.sh web
```

Nothing on this branch was edited after the build; `index.html` is a byte-identical
copy of the generated `GalleryApp.html` (only the filename differs).
