
xmake Lua script/plugin that generates an `xmake.lua` file from an `xmake.toml` file.

The `xtoml.lua` file can also be executed (by xmake) independently, so you can put that file directl in your repo and execute it in the root directory of your repo with: `xmake l xtoml.lua`

If you want to use as a plugin then first download this repo to your xmake plugins directory.

## Usage
```bash
xmake xtoml
```

## Example
```toml
[project]
name = "Application X"
description = "An app that does stuff."
version = "v0.0.1"
license = "MIT"
languages = [ "c++20", "c17" ]
warnings = [ "all", "error" ]
optimize = "fastest"

[requires]
fmt = "11.0.2"
zlib = [ "v1.3.1", { configs = { zutil = true } } ]

[requires.lua]
version = "latest"
configs = { shared = true }
system = false

[option.switch_safety]
cxxflags = [ "gcc::-Wswitch-enum", "clang::-Wswitch", "msvc::/W3058" ]

[target.appx]
kind = "binary"
options = "switch_safety"
files = [ "src/**.cpp", "external/gitsub/src/*.cpp" ]
includes = [ "include", "external/gitsub/include" ]
deps = "applib"
rpaths = "./"
packages = [ "lua", "fmt" ]

[target.applib]
kind = "static"
files = "lib/src/**.cpp"
includes = [ [ "include", { public = true } ],  # this nested array creates two
        [ "external/anothermodule/include" ] ]  # 'add_includedirs' xmake.lua entries
defines = [ "FAST", { inherited = true } ]
packages = [ "fmt", "zlib" ]
```


