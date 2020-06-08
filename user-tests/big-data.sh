#!/usr/bin/env bash

pre="https://iodatasets.blob.core.windows.net/iodataset/"
datasets=( "https://iodatasets.blob.core.windows.net/iodataset/130081_310927_bundle_archive.zip" # 2.29gb
        "https://iodatasets.blob.core.windows.net/iodataset/561256_1103067_bundle_archive.zip" # 1.03
        "https://iodatasets.blob.core.windows.net/iodataset/562468_1022626_bundle_archive.zip" # 1.19
)

# Warm the cache (store local) to exclude network variance
for file in "${datasets[@]}"; do
    if [ ! -e ${file#$pre} ]; then
        wget -q "${file}"
    fi
done

targ=$1
for file in "${datasets[@]}"; do
    mkdir -p "${targ}"
    tar xvz -C "${targ}" -f "${file}" >"${targ}/bigdata.out" 2>&1
    rm -rf "${targ}"
done
