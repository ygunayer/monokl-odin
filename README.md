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

#### Note on Virtual Environments
While it's a good practice to use virtual environments when working with Python, this script currently doesn't have any dependencies so it's fine to use it without one.

Having said that, if you extend the script and add some external dependencies via Pip and the like, I strongly recommend that you create a `requirements.txt` file to put your dependencies, and then create and use a virtual environment.

#### Using Pip
`requirements.txt`
```
requests==2.32.3
```

**Windows - Command Prompt**
```batch
> python -m venv .venv
> .\.venv\Scripts\Activate
> pip install -r requirements.txt
```

**Windows - Powershell Terminal**
```powershell
> python -m venv .venv
> & .\.venv\Scripts\Activate.ps1
> pip install -r requirements.txt
```

**Linux, MacOS**
```bash
$ python3 -m venv .venv
$ source .venv/bin/activate
$ pip install -r requirements.txt
```

### Using uv
It's the year 2025, so do yourself a favor and just go ahead and install [uv](https://docs.astral.sh/uv/)

Once installed, the commands above will be as easy as follows:

**Windows**
```powershell
> uv init
> uv venv
> uv add requests
> uv run build.py -h
```

**Linux, MacOS**
```powershell
$ uv init
$ uv venv
$ uv add requests
$ uv run build.py -h
```

## License
MIT
