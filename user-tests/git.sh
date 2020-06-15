#!/usr/bin/env bash

targ=$1
cache=$2
cd "${targ}" || exit 1
/usr/bin/git clone git@github.com:MicrosoftDocs/azure-docs.git >gitlog 2>&1
rm -rf azure-docs
