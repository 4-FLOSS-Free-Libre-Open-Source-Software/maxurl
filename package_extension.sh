#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

get_userscript_version() {
    cat $1 | grep '@version *[0-9.]* *$' | sed 's/.*@version *\([0-9.]*\) *$/\1/g'
}

USERVERSION=`get_userscript_version userscript.user.js`
MANIFESTVERSION=`cat manifest.json | grep '"version": *"[0-9.]*", *$' | sed 's/.*"version": *"\([0-9.]*\)", *$/\1/g'`

if [ -z "$USERVERSION" -o -z "$MANIFESTVERSION" ]; then
    echo Broken version regex
    exit 1
fi

if [ "$USERVERSION" != "$MANIFESTVERSION" ]; then
    echo 'Conflicting versions (userscript and manifest)'
    exit 1
fi

node ./gen_minified.js
MINVERSION=`get_userscript_version userscript_min.user.js`

if [ "$MINVERSION" != "$USERVERSION" ]; then
    echo 'Conflicting versions (userscript and minified)'
    exit 1
fi

cp site/style.css extension/options.css
cp userscript_smaller.user.js site/

echo Building Firefox extension

zipcmd() {
    zip -r "$1" LICENSE.txt manifest.json userscript.user.js lib/testcookie_slowaes.js lib/hls.js lib/dash.all.debug.js resources/logo_40.png resources/logo_48.png resources/logo_96.png resources/disabled_40.png resources/disabled_48.png resources/disabled_96.png extension -x "*~"
}

rm extension.xpi
zipcmd extension.xpi

FILES=$(unzip -l extension.xpi | awk '{print $4}' | awk 'BEGIN{x=0;y=0} /^----$/{x=1} {if (x==1) {x=2} else if (x==2) {print}}' | sed '/^ *$/d' | sort)

echo "$FILES" > files.txt
cat <<EOF >> files.txt
extension/
extension/background.js
extension/options.css
extension/options.html
extension/popup.html
extension/popup.js
lib/dash.all.debug.js
lib/hls.js
lib/testcookie_slowaes.js
LICENSE.txt
manifest.json
resources/disabled_40.png
resources/disabled_48.png
resources/disabled_96.png
resources/logo_40.png
resources/logo_48.png
resources/logo_96.png
userscript.user.js
EOF

DIFF="$(cat files.txt | sort | uniq -u)"

if [ ! -z "$DIFF" ]; then
    echo
    echo Wrong files
    exit 1
fi

rm files.txt


echo Building chrome extension
# This is based on http://web.archive.org/web/20180114090616/https://developer.chrome.com/extensions/crx#scripts

name=maxurl
crx="$name.crx"
pub="$name.pub"
sig="$name.sig"
zip="$name.zip"
key="$name.pem"

rm $zip $pub $sig
zipcmd $zip

# signature
openssl sha1 -sha1 -binary -sign "$key" < "$zip" > "$sig"

# public key
openssl rsa -pubout -outform DER < "$key" > "$pub" 2>/dev/null

byte_swap () {
  # Take "abcdefgh" and return it as "ghefcdab"
  echo "${1:6:2}${1:4:2}${1:2:2}${1:0:2}"
}

crmagic_hex="4372 3234" # Cr24
version_hex="0200 0000" # 2
pub_len_hex=$(byte_swap $(printf '%08x\n' $(ls -l "$pub" | awk '{print $5}')))
sig_len_hex=$(byte_swap $(printf '%08x\n' $(ls -l "$sig" | awk '{print $5}')))
(
  echo "$crmagic_hex $version_hex $pub_len_hex $sig_len_hex" | xxd -r -p
  cat "$pub" "$sig" "$zip"
) > "$crx"

echo
echo "Release checklist:"
echo
echo ' * Ensure xx00+ count is updated (userscript - greasyfork/oujs, reddit post, mozilla/opera, website)'
echo ' * Update greasyfork, oujs, firefox, opera, changelog.txt'
echo ' * git tag v'$USERVERSION
echo ' * Update userscript.user.js for site (but check about.js for site count before)'
echo ' * Update CHANGELOG.txt and Discord changelog'
