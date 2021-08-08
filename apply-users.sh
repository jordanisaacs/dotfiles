#!/bin/sh

pushd ~/.dotfiles
home-manager switch -f ./users/jd/home.nix
popd
