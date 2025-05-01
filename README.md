# monokl
Lightweight, cross-platform, minimalistic image viewer written in Odin.

It originally started as my attempts to learn Odin, but turned into a rewrite of [ygunayer/monokl](https://github.com/ygunayer/monokl) which was originally written in C++.

## Development
monokl is written in the Odin programming language, with scripts to ease the compilation process. Refer to individual subsections for more details about how to develop monokl.

### Prerequisites
- [Odin](https://github.com/odin-lang/Odin/)
- SDL3 development kit
- SDL3_image development kit
- (Optional) Python 3 for running the build script (3.10+ preferred)

## Building
While you can always use the Odin compiler to compile or run your program, you can also use the build script [build.py](./build.py).

Since this is script is written in Python, you will need to have Python3 installed on your machine to run it.

Refer to the self-documentation of the script for more info about what you can do with it:

**Windows**
```batch
> py build.py -h

```

**Linux, MacOS**
```bash
$ ./build.py -h
```

## License
MIT
