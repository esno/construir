# how to setup

## dependencies

* git
* lua54

## build

    git clone --recurse-submodules git@github.com:esno/construir.git

    cmake -B ./build/fiddle ./fiddle -DCMAKE_INSTALL_PREFIX=./build/image -DWITH_JOURNALD=0; make -C ./build/fiddle; make -C ./build/fiddle install
    cmake -B ./build/construir ./ -DCMAKE_INSTALL_PREFIX=./build/image && make -C ./build/construir && make -C ./build/construir install

# usage

## recipe sample

    cat $CONSTRUIR_AQUI/recipes/binutils.lua
    pkg.name = "binutils"
    pkg.version = "2.43.1"

    pkg.scm = {
      git = {{
        remote = "git://sourceware.org/git/binutils-gdb.git",
        rev = string.format("%s-%s_%s_%s", pkg.name, pkg.major, pkg.minor, pkg.patch)
      }}
    }

    pkg.configure = function()

    end

## build a recipe

    export CONSTRUIR_AQUI="$(pwd)/lfs"
    ./build/image/libexec/construir binutils
    == construir: a custom linux distribution of your needs
    -> binutils parse recipe
    -> binutils/2.43.1 add task git_clone git://sourceware.org/git/binutils-gdb.git
    -> binutils/2.43.1 add task git_checkout binutils-gdb.git -> binutils-2_43_1
    ** binutils/2.43.1 fetch git://sourceware.org/git/binutils-gdb.git
    ** binutils/2.43.1 unpack binutils-gdb.git -> binutils-2_43_1
