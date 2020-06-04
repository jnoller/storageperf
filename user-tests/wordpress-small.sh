#!/usr/bin/env bash

targ=$1

f="latest.tar.gz"
if [ ! -e $f ]; then
    wget -qO- https://wordpress.org/latest.tar.gz
fi

for n in $(seq 1 5); do
    mkdir -p $targ
    tar xvz -C "${targ}" -f $f >wordpress.out 2>&1
    rm -rf "${targ}"
done
