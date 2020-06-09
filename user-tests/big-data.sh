#!/usr/bin/env bash

pre="https://iodatasets.blob.core.windows.net/iodataset/"
datasets=( "https://iodatasets.blob.core.windows.net/iodataset/130081_310927_bundle_archive.zip" # 2.29gb
        "https://iodatasets.blob.core.windows.net/iodataset/561256_1103067_bundle_archive.zip" # 1.03
        "https://iodatasets.blob.core.windows.net/iodataset/562468_1022626_bundle_archive.zip" # 1.19
)

targ=$1
cd "${targ}" || exit 1

# Warm the cache (store local) to exclude network variance
skr="${targ}/databass"
mkdir -p "${skr}"
for file in "${datasets[@]}"; do
    fname="${file#$pre}"
    fp="${targ}/${fname}"
    if [ ! -f "${fp}" ]; then
        echo "downloading data file %{fname}"
        wget -cq "${file}"
    fi
    unzip "${fp}" -d "${skr}" >ziplog 2>&1 || exit 1
    rm -rf "${skr}" && mkdir -p "${skr}"
done

for file in "${datasets[@]}"; do
    mkdir -p "${targ}"
    unzip "${file#$pre}" -d "${targ}/${file#$pre}" >ziplog 2>&1
    find . -type f -exec touch {} +

    rm -rf "${targ}/${file#$pre:?}"
done
