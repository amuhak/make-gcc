#!/bin/bash
echo "This should be run in an empty folder"

no_of_cores=$(nproc --all)

echo "You have ${no_of_cores} core/theads"

echo "Cloning"

git clone git://gcc.gnu.org/git/gcc.git

read -p "Enter version number you want to build: " number

# make sure that $number has 2 '.'
period_count=$(echo "$number" | grep -o "\." | wc -l)

if [ "$period_count" -eq 2 ]; then
    echo "Version number is valid: $number"
else
    echo "You input: $number dosn't have 2 '.' so it isnt a corect version"
    echo "You must input something like 14.1.0"
    echo "exiting"
    exit 1
fi

rm build -rf

cd gcc

echo "entering ./gcc and cleaning git"

git clean -fd
git reset --hard origin/master
git fetch --all
git reset --hard origin/master

tagname="releases/gcc-${number}"

echo "checking out $tagname"

if ! git checkout "$tagname"; then
    echo "Failed to check out tag $tagname. Please ensure it's a valid GCC version."
    exit 1
fi

echo "Make sure that that ^^^^^^ ran correctly, i.e. you have a real gcc version"

# geting some prerequisites
echo "geting some prerequisites"

contrib/download_prerequisites

cd ..

echo "The version that will be built: $number"

echo "installing some more prerequisites"
sudo apt install bzip2 flex build-essential

mkdir build
cd build

echo "Configuring"

current_dir=$(pwd)

prefix_path="${current_dir}/../gcc-${number}"

../gcc/configure -v --build=x86_64-linux-gnu --host=x86_64-linux-gnu --target=x86_64-linux-gnu "--prefix=${prefix_path}" --enable-checking=release --enable-languages=c,c++,fortran,go --disable-multilib

echo "Building"

make -j "${no_of_cores}"

echo "Removing temp files"

echo "installing"

sudo make install-strip

echo "You will find the binarys in ./gcc-${number}/bin"
echo "Done 🎉🎉🎉"

cd ..
