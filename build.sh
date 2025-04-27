#!/bin/bash
set -euo pipefail

# Record start time of the entire script
script_start_time=$(date +%s)

# --- Configuration ---
DEFAULT_GCC_GIT_URL="git://gcc.gnu.org/git/gcc.git"
GCC_SOURCE_DIR="gcc"
BUILD_DIR="build"
run_tests=false 

# --- Helper Functions ---
usage() {
  echo "Usage: $0 [--run-tests] [-v <version>]"
  echo "  Builds GCC from source."
  echo ""
  echo "Options:"
  echo "  --run-tests        Run the GCC test suite after build."
  echo "  -v, --version      Specify the exact GCC version to build (e.g., 13.2.0)."
  echo "  -h, --help         Display this help message."
  exit 1
}

# --- Option Parsing (with getopt) ---
run_tests=false
specified_version="" # Initialize variable to store user-specified version

# Parse both short and long options
PARSED=$(getopt -o v:h --long version:,run-tests,help -- "$@") || usage
eval set -- "$PARSED"

# Handle the new --run-tests flag
while true; do
  case "$1" in
    -v | --version)
      specified_version="$2"
      shift 2
      ;;
    --run-tests)
      run_tests=true
      shift
      ;;
    -h | --help)
      usage
      ;;
    --) # End of options
      shift
      break
      ;;
    *) # Should not happen with getopt
      echo "Internal error!" >&2
      exit 1
      ;;
  esac
done

# Check for leftover non-option arguments (should be none)
if [ "$#" -ne 0 ]; then
   echo "Error: Unexpected arguments: $*" >&2
   usage
fi


# --- Script Start ---
echo "Starting GCC Build Script"

# Check if the current directory is empty (warn if not)
if [ "$(ls -A)" != "" ] && [ "$(ls -A)" != "${GCC_SOURCE_DIR}" ] && [ "$(ls -A)" != "${BUILD_DIR}" ] ; then
    # Be a bit smarter: ignore the source and build dirs if they already exist
    non_build_files=$(ls -A | grep -vE "^(${GCC_SOURCE_DIR}|${BUILD_DIR})$" || true)
    if [ -n "$non_build_files" ]; then
        echo "Warning: This directory contains unexpected files/folders:"
        echo "$non_build_files"
        echo "It is recommended to run this script in an empty or clean folder."
        # Optionally add a prompt here to continue or exit
        # read -p "Continue anyway? (y/N): " confirm && [[ $confirm == [yY] ]] || exit 1
    fi
fi


# Update package lists and install required dependencies
echo "Please ensure you install: build-essential flex bzip2 gawk"

# Determine the number of cores for parallel build
no_of_cores=$(nproc --all)
echo "Detected ${no_of_cores} core(s)/thread(s) for parallel build."

# --- Get GCC Source Code ---
latest_version=""
if [ -d "${GCC_SOURCE_DIR}/.git" ]; then
    echo "GCC repository '${GCC_SOURCE_DIR}' already exists. Updating..."
    cd "${GCC_SOURCE_DIR}"
    git fetch --all --tags
    # Optional: reset to remote master/main if needed, but fetching tags is usually enough
    # git reset --hard origin/$(git rev-parse --abbrev-ref origin/HEAD)
    echo "Determining the latest GCC release version from existing repo..."
    latest_version=$(git tag -l 'releases/gcc-*' | grep -v 'rc' | grep -v 'snapshot' | sort -V | tail -n 1 | sed 's|^releases/gcc-||')
    cd ..
else
    echo "Cloning GCC repository from ${DEFAULT_GCC_GIT_URL}..."
    git clone --bare "${DEFAULT_GCC_GIT_URL}" "${GCC_SOURCE_DIR}.git"
    # Create a working directory from the bare repo
    git --git-dir="${GCC_SOURCE_DIR}.git" --work-tree="${GCC_SOURCE_DIR}" checkout -f
    cd "${GCC_SOURCE_DIR}"
    echo "Determining the latest GCC release version..."
    # Fetch tags explicitly after bare clone and checkout might be needed
    git fetch --all --tags
    latest_version=$(git tag -l 'releases/gcc-*' | grep -v 'rc' | grep -v 'snapshot' | sort -V | tail -n 1 | sed 's|^releases/gcc-||')
    cd ..
fi

if [ -z "$latest_version" ]; then
    echo "Error: Could not automatically determine the latest GCC version from git tags." >&2
    echo "Please specify a version using the -v flag." >&2
    exit 1
fi
echo "Latest detected GCC release version: ${latest_version}"


# --- Determine Version to Build ---
version_to_build=""
if [ -n "$specified_version" ]; then
    echo "Using user-specified version: ${specified_version}"
    version_to_build="$specified_version"
else
    echo "Using latest detected version: ${latest_version}"
    version_to_build="$latest_version"
fi

# Validate the final version string format (X.Y.Z)
period_count=$(echo "$version_to_build" | grep -o "\." | wc -l)
if [ "$period_count" -ne 2 ]; then
    echo "Error: Invalid version format for '${version_to_build}'."
    echo "Version must be in the format X.Y.Z (e.g., 14.1.0)"
    exit 1
fi
echo "Selected version for build: ${version_to_build}"
tag_name="releases/gcc-${version_to_build}"


# --- Prepare Build ---
# Enter the gcc source directory
cd "${GCC_SOURCE_DIR}"

echo "Checking out tag: ${tag_name}"
# Use git work-tree and git-dir for robustness if we didn't clone normally
if ! git checkout "${tag_name}"; then
    echo "Error: Failed to check out tag ${tag_name}." >&2
    echo "Please ensure it's a valid GCC release version available in the repository." >&2
    # List available release tags for user help
    echo "Available release tags (may be truncated):"
    git tag -l 'releases/gcc-*' | grep -v 'rc' | grep -v 'snapshot' | sort -V | tail -n 20
    cd ..
    exit 1
fi

echo "Downloading prerequisites..."
./contrib/download_prerequisites

# Go back to the base directory
cd ..

# Prepare the build directory (clean slate)
echo "Preparing build directory '${BUILD_DIR}'..."
rm -rf "${BUILD_DIR}"
mkdir "${BUILD_DIR}"

# Define installation prefix path
install_prefix_path="$(pwd)/gcc-${version_to_build}" # Install in a versioned subdir of the current dir


# --- Configure Build ---
# Enter the build directory
cd "${BUILD_DIR}"
echo "Configuring GCC build (version ${version_to_build}) in $(pwd)"
echo "Installation prefix: ${install_prefix_path}"

../${GCC_SOURCE_DIR}/configure -v \
    --build=x86_64-linux-gnu \
    --host=x86_64-linux-gnu \
    --target=x86_64-linux-gnu \
    --prefix="${install_prefix_path}" \
    --program-suffix="-${version_to_build}" \
    --enable-checking=release \
    --enable-languages=c,c++,objc,fortran,ada,go,d \
    --disable-multilib \
    --disable-bootstrap # Optional: Speeds up build, but less thoroughly tested GCC. Remove if you prefer bootstrapping.
    # Consider adding: --enable-offload-targets=native # if you need OpenMP/OpenACC offloading

echo "Starting GCC build with ${no_of_cores} cores..."
start_time_build=$(date +%s)
make -j "${no_of_cores}"
end_time_build=$(date +%s)
duration_build=$((end_time_build - start_time_build))
echo "Build finished in $(($duration_build / 60)) minutes and $(($duration_build % 60)) seconds."


echo "Installing GCC..."
# Use install-strip to save space by removing debug symbols from installed binaries
sudo make install-strip

# --- Run Tests (Optional) ---
if [ "$run_tests" = true ]; then
    echo "Running GCC test suite (make check)... This may take a very long time."
    # Ensure we are in the build directory
    # The number of cores for testing might need adjustment, sometimes -jN fails for 'check'
    # Using a lower number or just 'make check' might be more stable.
    start_time_test=$(date +%s)
    make -j "${no_of_cores}" check || echo "Warning: 'make check' reported errors. Check logs in '${BUILD_DIR}' for details."
    end_time_test=$(date +%s)
    duration_test=$((end_time_test - start_time_test))
    echo "Test suite finished in $(($duration_test / 60)) minutes and $(($duration_test % 60)) seconds."

else
    echo "Skipping test suite (--run-tests not specified)."
fi

# Go back to the base directory
cd ..

# --- Completion ---
# Record end time of the entire script
script_end_time=$(date +%s)
script_duration=$((script_end_time - script_start_time))

echo ""
echo "-------------------------------------"
echo "GCC build and installation complete!"
echo "Version: ${version_to_build}"
echo "Installed to: ${install_prefix_path}"
echo "-------------------------------------"
echo "Build time: $(($duration_build / 60)) minutes and $(($duration_build % 60)) seconds."
if [ "$run_tests" = true ]; then
    echo "Test time:  $(($duration_test / 60)) minutes and $(($duration_test % 60)) seconds."
fi
echo "Total script execution time: $(($script_duration / 60)) minutes and $(($script_duration % 60)) seconds."
echo ""
echo "To use this GCC version, you might need to:"
echo "1. Add ${install_prefix_path}/bin to your PATH:"
echo "   export PATH=\"${install_prefix_path}/bin:\$PATH\""
echo "2. Add ${install_prefix_path}/lib64 (or /lib) to your LD_LIBRARY_PATH:"
echo "   export LD_LIBRARY_PATH=\"${install_prefix_path}/lib64:\$LD_LIBRARY_PATH\""
echo "(Add these lines to your ~/.bashrc or ~/.profile for persistence)"
echo ""
echo "You can invoke the compiler directly using gcc-${version_to_build}, g++-${version_to_build}, etc."

exit 0