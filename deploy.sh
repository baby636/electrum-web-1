#!/bin/bash
# cron job for the webserver
set -ex

REPODIR="$(dirname "$(readlink -e "$0")")"
cd "$REPODIR"

date -u

# fixme: we should not poll github
git fetch github
echo "latest website commit $(git rev-parse github/master)"

LOCAL_VERSION=$(cat version|jq '.version'|tr -d '"')
VERSION=$(git show github/master:version|jq '.version'|tr -d '"')

echo "local version: $LOCAL_VERSION "
echo "github version: $VERSION "

sftp -oBatchMode=no -b - pubwww@uploadserver << !
   cd electrum-downloads-airlock
   get website.ThomasV.asc
   get website.sombernight_releasekey.asc
   bye
!

git rev-parse github/master | gpg --no-default-keyring --keyring "$REPODIR/gpg/thomasv.gpg" --verify website.ThomasV.asc -
git rev-parse github/master | gpg --no-default-keyring --keyring "$REPODIR/gpg/sombernight_releasekey.gpg" --verify website.sombernight_releasekey.asc -

echo "website signature verified"

# Just updating website; no new release
if [ $LOCAL_VERSION = $VERSION ];
then
    echo "updating website and exiting"
    git merge --ff-only FETCH_HEAD
    exit 0
fi

# As versions mismatched, there is a new release.
# 1. read from the airlock directory
rm -rf /tmp/airlock
mkdir /tmp/airlock
pushd /tmp/airlock

sftp -oBatchMode=no -b - pubwww@uploadserver << !
   cd electrum-downloads-airlock
   cd $VERSION
   mget *
   bye
!

# verify signatures of binaries
dmg=electrum-$VERSION.dmg
for item in ./*
do
    if [[ "$item" == *".asc" ]]; then
        :  # skip verifying signature-files
    else
        # All other files should be reproducible binaries; verify two sigs.
        # In case we upload any other file for whatever reason, both sigs are needed too.
        gpg --no-default-keyring --keyring "$REPODIR/gpg/thomasv.gpg" --verify "$item.ThomasV.asc" "$item"
        gpg --no-default-keyring --keyring "$REPODIR/gpg/sombernight_releasekey.gpg" --verify "$item.sombernight_releasekey.asc" "$item"
    fi
done

echo "verification passed"

# publish files
sftp -oBatchMode=no -b - pubwww@uploadserver << !
   cd electrum-downloads
   mkdir $VERSION
   cd $VERSION
   mput *
   bye
!

# update website
popd
git merge --ff-only FETCH_HEAD

# todo: clear cloudflare cache
