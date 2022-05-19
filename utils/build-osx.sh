#!/usr/bin/env bash
set -e

# We start in the directory where this script is located
cd "$( dirname "${BASH_SOURCE[0]}" )/."
source build-common.sh
cd ..
# Now in project-root

# Overriding this function
function create_virtualenv_for_pyinstaller {
    if [ -d .buildenv ]; then
        echo "    --> Deleting .buildenv"
        rm -rf .buildenv
    fi
    # linux:
    # virtualenv --python=python3 .buildenv
    # we do:
    virtualenv --python=/usr/local/bin/python3 .buildenv
    source .buildenv/bin/activate
    pip3 install -r test_requirements.txt
}


function sub_help {
    cat << EOF
# possible prerequisites
# brew install gmp # to prevent module 'embit.util' has no attribute 'ctypes_secp256k1'
# npm install --global create-dmg

# Download into torbrowser:
# wget -P torbrowser https://archive.torproject.org/tor-package-archive/torbrowser/10.0.15/TorBrowser-10.0.15-osx64_en-US.dmg

# Currently, only MacOS Catalina is supported to build the dmg-file
# Therefore we expect xcode 12.1 (according to google)
# After installation of xcode: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# otherwise you get xcrun: error: unable to find utility "altool", not a developer tool or in PATH

# catalina might have a a too old version of bash. You need at least 4.0 or so
# 3.2 is too low definitely
# brew install bash

# Fill the keychain with your password like this
# xcrun altool --store-password-in-keychain-item AC_PASSWORD -u '<your apple id>' -p apassword

# You need to participate in the Apple-Developer Program (Eur 99,- yearly fee)
# https://developer.apple.com/programs/enroll/ 

# Then you need to create a cert which you need to store in the keychain
# https://developer.apple.com/account/resources/certificates/list

# If you have the common issue "errSecInternalComponent" while signing the code:
# https://medium.com/@ceyhunkeklik/how-to-fix-ios-application-code-signing-error-4818bd331327

# create-dmg issue? Note that there are 2 create-dmg scripts out there. We use:
# https://github.com/sindresorhus/create-dmg

# Example-call:
# ./build-osx.sh --debug --version v1.7.0-pre1 --appleid "Kim Neunert (FWV59JHV83)" --mail "kim@specter.solutions" make-hash
EOF
}

appleid=""

while [[ $# -gt 0 ]]
  do
  arg="$1"
  case $arg in
      "" | "-h" | "--help")
        sub_help
        exit 0
        shift
        ;;
      --debug)
        set -x
        DEBUG=true
        shift
        ;;
      --version)
        version=$2
        shift
        shift
        ;;
      --appleid)
        appleid=$2
        shift
        shift
        ;;
      --mail)
        mail=$2
        shift
        shift
        ;;
      specterd)
        build_specterd=True
        shift
        ;;
      make-hash)
        make_hash=True
        shift
        ;;
      electron)
        build_electron=True
        shift
        ;;
      sign)
        build_sign=True
        shift
        ;;
      help)
        sub_help
        shift
        ;;
      *)
          shift
          sub_${arg} $@ && ret=0 || ret=$?
          if [ "$ret" = 127 ]; then
              echo "Error: '$arg' is not a known subcommand." >&2
              echo "       Run '$progname --help' for a list of known subcommands." >&2
              exit 1
          else
              exit $ret_value
          fi
          ;;
  esac
  done

echo "    --> This build got triggered for version $version"

echo $version > pyinstaller/version.txt

specify_app_name

if [[ "$build_specterd" = "True" ]]; then
  create_virtualenv_for_pyinstaller
  build_pypi_pckgs_and_install
  install_build_requirements
  cleanup
  building_app
fi

if [[ "$build_electron" = "True" ]]; then
  prepare_npm
  make_hash_if_necessary



  npm i
  if [[ "${appleid}" == '' ]]
  then
      echo "`jq '.build.mac.identity=null' package.json`" > package.json
  else
      echo "`jq '.build.mac.identity="'"${appleid}"'"' package.json`" > package.json
  fi

  building_electron_app

fi

if [[ "$build_sign" = "True" ]]; then
  if [[ "$appleid" != '' ]]
  then
    macos_code_sign
  fi

  echo "    --> Making the release-zip"
  mkdir release

  create-dmg electron/dist/mac/${specterimg_filename}.app --identity="Developer ID Application: ${appleid}"
  # create-dmg doesn't create the prepending "v" to the version
  node_comp_version=$(python3 -c "print('$version'[1:])")
  mv "electron/dist/${specterimg_filename}-${node_comp_version}.dmg" release/${specterimg_filename}-${version}.dmg

  cd dist # ./pyinstaller/dist
  zip ../release/${specterd_filename}-${version}-osx.zip ${specterd_filename}
  cd .. # ./pyinstaller

  sha256sum ./release/${specterd_filename}-${version}-osx.zip
  sha256sum ./release/${specterimg_filename}-${version}.dmg
fi

if [ "$app_name" == "specter" ]; then
  echo "--------------------------------------------------------------------------"
  echo "In order to upload these artifacts to github, do:"
  echo "export CI_PROJECT_ROOT_NAMESPACE=cryptoadvance"
  echo "export CI_COMMIT_TAG=$version"
  echo "export GH_BIN_UPLOAD_PW=YourSecretHere"
  echo "python3 ../utils/github.py upload ./release/specterd-${version}-osx.zip"
  echo "python3 ../utils/github.py upload ./release/SpecterDesktop-${version}.dmg"
  echo "cd release"
  echo "sha256sum * > SHA256SUMS-macos"
  echo "python3 ../../utils/github.py upload SHA256SUMS-macos"
  echo "gpg --detach-sign --armor SHA256SUMS-macos"
  echo "python3 ../../utils/github.py upload SHA256SUMS-macos.asc"
fi