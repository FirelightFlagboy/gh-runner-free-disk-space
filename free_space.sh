#!/bin/bash

setup_rmz() {
  curl -fsSL --tlsv1.2 --proto '=https' https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
  cargo binstall -qy rmz
  sudo ln -s ~/.cargo/bin/rmz /usr/local/bin/rmz
}

list_installed_dpkg() {
  dpkg-query -W -f='${Package}\n' "$@" | grep -v -E '^(base-files|core-utils|libc6)$'
}

get_available_space() {
  df / | awk 'NR==2 {print $4}'
}

format_byte_count() {
  numfmt --to=iec-i --suffix=B --padding=7 $(($1 * 1000))
}

print_saved_space_and_time() {
  local saved=$1
  local time=$2
  local title=$3
  echo "$title: Saved $(format_byte_count $saved) in ${time} seconds"
}

INITIAL_SPACE=$(get_available_space)
setup_rmz 

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
  
  print_saved_space_and_time $saved $time_taken "$title"
}

# Remove Android library
if [[ ${{ inputs.android }} == 'true' ]]; then
  remove_and_measure "Android library" sudo rmz -f /usr/local/lib/android
fi

# Remove .NET runtime
if [[ ${{ inputs.dotnet }} == 'true' ]]; then
  remove_and_measure ".NET runtime" sudo rmz -f /usr/share/dotnet
fi

# Remove Haskell runtime
if [[ ${{ inputs.haskell }} == 'true' ]]; then
  remove_and_measure "Haskell runtime" sudo rmz -f /opt/ghc /usr/local/.ghcup
fi

# Remove large packages
if [[ ${{ inputs.large-packages }} == 'true' ]]; then
  remove_and_measure "Large misc. packages" bash -c '
    pkgs=$(list_installed_dpkg "aspnetcore-*" "dotnet-*" "llvm-*" "*php*" "mongodb-*" "mysql-*" azure-cli google-chrome-stable firefox powershell mono-devel libgl1-mesa-dri "google-cloud-*" "gcloud-*")
    gcloud_prerm="#!/bin/sh
    [ -d \"/usr/lib/google-cloud-sdk\" ] && sudo rmz -f /usr/lib/google-cloud-sdk"
    echo "$gcloud_prerm" | sudo tee /var/lib/dpkg/info/google-cloud-cli-anthoscli.prerm /var/lib/dpkg/info/google-cloud-cli.prerm >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y $pkgs
    sudo apt-get autoremove -y
    sudo apt-get clean
  '
fi

# Remove Docker images
if [[ ${{ inputs.docker-images }} == 'true' ]]; then
  remove_and_measure "Docker images" sudo docker system prune -af
fi

# Remove tool cache
if [[ ${{ inputs.tool-cache }} == 'true' ]]; then
  remove_and_measure "Tool cache" sudo rmz -f "$AGENT_TOOLSDIRECTORY"
fi

# Remove Swap storage
if [[ ${{ inputs.swap-storage }} == 'true' ]]; then
  remove_and_measure "Swap storage" bash -c '
    sudo swapoff -a
    sudo rmz -f /mnt/swapfile
    free -h
  '
fi

sudo rm -f /usr/local/bin/rmz

FINAL_SPACE=$(get_available_space)
TOTAL_SAVED=$((FINAL_SPACE - INITIAL_SPACE))

echo "Total space saved: $(format_byte_count $TOTAL_SAVED)"
