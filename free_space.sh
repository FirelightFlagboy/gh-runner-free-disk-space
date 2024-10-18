#!/bin/bash

set -e

setup_rmz() {
  # Suppress all output from curl and cargo-binstall
  curl -fsSL --tlsv1.2 --proto '=https' https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash > /dev/null 2>&1
  cargo binstall -qy rmz > /dev/null 2>&1
  sudo ln -sf ~/.cargo/bin/rmz /usr/local/bin/rmz
  echo "rmz setup completed"
}

get_available_space() {
  df / | awk 'NR==2 {print $4}'
}

format_byte_count() {
  numfmt --to=iec-i --suffix=B --padding=7 "${1}"
}

remove_and_measure() {
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
}

INITIAL_SPACE=$(get_available_space)
setup_rmz

if [[ $INPUT_ANDROID == 'true' ]]; then
  remove_and_measure "Android library" sudo rm -rf /usr/local/lib/android
fi

if [[ $INPUT_DOTNET == 'true' ]]; then
  remove_and_measure ".NET runtime" sudo rm -rf /usr/share/dotnet
fi

if [[ $INPUT_HASKELL == 'true' ]]; then
  remove_and_measure "Haskell runtime" sudo rm -rf /opt/ghc /usr/local/.ghcup
fi

if [[ $INPUT_LARGE_PACKAGES == 'true' ]]; then
  remove_and_measure "Large misc. packages" bash -c '
    pkgs=$(dpkg-query -W -f='${Package}\n' aspnetcore-* dotnet-* llvm-* *php* mongodb-* mysql-* azure-cli google-chrome-stable firefox powershell mono-devel libgl1-mesa-dri google-cloud-* gcloud-* | grep -v -E "^(base-files|core-utils|libc6)$")
    if [ ! -z "$pkgs" ]; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y $pkgs
      sudo apt-get autoremove -y
      sudo apt-get clean
    fi
  '
fi

if [[ $INPUT_DOCKER_IMAGES == 'true' ]]; then
  remove_and_measure "Docker images" sudo docker system prune -af
fi

if [[ $INPUT_TOOL_CACHE == 'true' ]]; then
  remove_and_measure "Tool cache" sudo rm -rf "$AGENT_TOOLSDIRECTORY"
fi

if [[ $INPUT_SWAP_STORAGE == 'true' ]]; then
  remove_and_measure "Swap storage" bash -c '
    sudo swapoff -a
    sudo rm -f /mnt/swapfile
  '
fi

FINAL_SPACE=$(get_available_space)
TOTAL_SAVED=$((FINAL_SPACE - INITIAL_SPACE))

echo "Total space saved: $(format_byte_count $TOTAL_SAVED)"
