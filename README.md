# how to setup

## dependencies

* git
* lua54

## build

    git clone --recurse-submodules git@github.com:esno/construir.git

    cd ./construir
    ./build.sh

# usage

frickle will be a reference linux distribution of construir.
it is available as submodule in [frickle](https://github.com/esno/frickle)

## build a recipe

    export CONSTRUIR_AQUI="$(pwd)/frickle"
    ./build/image/libexec/construir binutils
    == construir: a custom linux distribution of your needs
    -> binutils parse recipe
    -> binutils/2.43.1 add task git_clone git://sourceware.org/git/binutils-gdb.git
    -> binutils/2.43.1 add task git_checkout binutils-gdb.git -> binutils-2_43_1
    ** binutils/2.43.1 fetch git://sourceware.org/git/binutils-gdb.git
    ** binutils/2.43.1 unpack binutils-gdb.git -> binutils-2_43_1
