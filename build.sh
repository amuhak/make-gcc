#!/bin/bash
set -euo pipefail

# Check if the current directory is empty (warn if not)
if [ "$(ls -A)" ]; then
    echo "Warning: This directory is not empty. It is recommended to run this script in an empty folder."
fi

# Update package lists and install required dependencies
echo "Updating package lists..."
sudo apt-get update

echo "Installing required dependencies..."
sudo apt install bzip2 flex build-essential -y

# Determine the number of cores for parallel build
no_of_cores=$(nproc --all)
echo "You have ${no_of_cores} core(s)/thread(s) available."

# Use the GCC repository if it exists; otherwise, clone it.
if [ -d "gcc" ]; then
    echo "GCC repository already exists. Updating the repository..."
    cd gcc
    git fetch --all
    git reset --hard origin/master
    cd ..
else
    echo "Cloning GCC repository..."
    git clone git://gcc.gnu.org/git/gcc.git
fi

# Prompt user for the GCC version to build
read -p "Enter the GCC version you want to build (e.g., 14.1.0): " version

# Validate that the version string has exactly two dots (format X.Y.Z)
period_count=$(echo "$version" | grep -o "\." | wc -l)
if [ "$period_count" -ne 2 ]; then
    echo "Invalid version format: $version"
    echo "You must input a version like 14.1.0 (i.e., X.Y.Z)"
    echo "Exiting."
    exit 1
fi
echo "Version number is valid: $version"

# Prepare the build directory
rm -rf build
mkdir build

# Enter the gcc source directory and check out the specified tag
cd gcc
echo "Checking out tag: releases/gcc-${version}"
if ! git checkout "releases/gcc-${version}"; then
    echo "Failed to check out tag releases/gcc-${version}. Please ensure it's a valid GCC version."
    exit 1
fi

echo "Downloading prerequisites..."
./contrib/download_prerequisites

cd ..

echo "The version that will be built: $version"

# Create and enter the build directory
cd build
current_dir=$(pwd)
prefix_path="${current_dir}/../gcc-${version}"

echo "Configuring GCC build..."
../gcc/configure -v \
    --build=x86_64-linux-gnu \
    --host=x86_64-linux-gnu \
    --target=x86_64-linux-gnu \
    --prefix="${prefix_path}" \
    --program-suffix="-${version}" \
    --enable-checking=release \
    --enable-languages=c,c++,objc,fortran,ada,go,d \
    --disable-multilib

echo "Building GCC with ${no_of_cores} cores..."
make -j "${no_of_cores}"

echo "Installing GCC..."
sudo make install-strip

echo "GCC build and installation complete!"
echo "You can find the installed GCC binaries in: ${prefix_path}/bin"
