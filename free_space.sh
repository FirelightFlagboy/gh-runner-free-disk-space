#!/bin/bash

set -e

setup_rmz() {
  curl -fsSL --tlsv1.2 --proto '=https' https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash > /dev/null 2>&1
  cargo binstall -qy rmz > /dev/null 2>&1
  sudo ln -sf ~/.cargo/bin/rmz /usr/local/bin/rmz
  echo "rmz setup completed"
}

list_installed_dpkg() {
    dpkg --get-selections $@ | grep -v deinstall | awk '{print $1}'
}

get_available_space() {
  df -a $1 | awk 'NR > 1 {avail+=$4} END {print avail}'
}

format_byte_count() {
  numfmt --to=iec-i --suffix=B --padding=7 $1'000'
}

remove_and_measure() {
  echo ""
  local title=$1
  shift
  local start_time=$(date +%s)
  local before=$(get_available_space)
  
  "$@"
  
  local after=$(get_available_space)
  local end_time=$(date +%s)
  local saved=$((after - before))
  local time_taken=$((end_time - start_time))
  
  echo "$title: Saved $(format_byte_count $saved) in ${time_taken} seconds"
  echo ""
}

INITIAL_SPACE=$(get_available_space)
setup_rmz

if [[ $INPUT_ANDROID == 'true' ]]; then
  remove_and_measure "Android library" sudo rmz -rf /usr/local/lib/android
fi

if [[ $INPUT_DOTNET == 'true' ]]; then
  remove_and_measure ".NET runtime" sudo rmz -rf /usr/share/dotnet
fi

if [[ $INPUT_HASKELL == 'true' ]]; then
  remove_and_measure "Haskell runtime" sudo rmz -rf /opt/ghc /usr/local/.ghcup
fi

if [[ $INPUT_LARGE_PACKAGES == 'true' ]]; then
  remove_and_measure "Large misc. packages" bash -c '
    pkgs=$(list_installed_dpkg "aspnetcore-*" "dotnet-*" "llvm-*" "*php*" "mongodb-*" "mysql-*" azure-cli google-chrome-stable firefox powershell mono-devel libgl1-mesa-dri "google-cloud-*" "gcloud-*" || true)
    
    gcloud_prerm='"'"'#!/bin/sh
    echo $0
    if [ -d "/usr/lib/google-cloud-sdk" ]; then
        find /usr/lib/google-cloud-sdk -type f -delete -print | wc -l
        sudo rmz -rf /usr/lib/google-cloud-sdk
        find /usr/share/man -type f -name "gcloud*" -delete -print | wc -l
    fi'"'"'

    echo "$gcloud_prerm" | sudo tee /var/lib/dpkg/info/google-cloud-cli-anthoscli.prerm >/dev/null
    echo "$gcloud_prerm" | sudo tee /var/lib/dpkg/info/google-cloud-cli.prerm >/dev/null

    sudo DEBIAN_FRONTEND=noninteractive apt-get remove --autoremove -y $pkgs
    sudo apt-get clean
  '
  echo ""
fi

if [[ $INPUT_DOCKER_IMAGES == 'true' ]]; then
  remove_and_measure "Docker images" sudo docker system prune -af
fi

if [[ $INPUT_TOOL_CACHE == 'true' ]]; then
  remove_and_measure "Tool cache" sudo rmz -rf "$AGENT_TOOLSDIRECTORY"
fi

if [[ $INPUT_SWAP_STORAGE == 'true' ]]; then
  remove_and_measure "Swap storage" bash -c '
    sudo swapoff -a
    sudo rmz -f /mnt/swapfile
  '
fi

sudo rm -f /usr/local/bin/rmz
FINAL_SPACE=$(get_available_space)
TOTAL_SAVED=$((FINAL_SPACE - INITIAL_SPACE))

echo "Total space saved: $(format_byte_count $TOTAL_SAVED)"
