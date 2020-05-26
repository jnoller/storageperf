#!/usr/bin/env bash

targ=$1
wget -qO- https://wordpress.org/latest.tar.gz | tar xvz -C "${targ}" >wordpress.out 2>&1
